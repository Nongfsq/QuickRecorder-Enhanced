import CRNNoise
import Foundation

public enum RNNoiseProcessorError: Error {
    case missingModel
    case modelLoadFailed
    case stateCreationFailed
    case invalidFrameSize(Int)
}

public final class RNNoiseFrameProcessor {
    public static let sampleRate = 48_000
    public static let frameSize = 480

    private var model: OpaquePointer?
    private var state: OpaquePointer?

    public init() throws {
        guard let modelURL = Bundle.module.url(forResource: "weights_blob", withExtension: "bin") else {
            throw RNNoiseProcessorError.missingModel
        }
        model = modelURL.path.withCString { rnnoise_model_from_filename($0) }
        guard let model else { throw RNNoiseProcessorError.modelLoadFailed }
        state = rnnoise_create(model)
        guard state != nil else {
            rnnoise_model_free(model)
            self.model = nil
            throw RNNoiseProcessorError.stateCreationFailed
        }
    }

    deinit {
        if let state { rnnoise_destroy(state) }
        if let model { rnnoise_model_free(model) }
    }

    public func process(frame: [Float]) throws -> [Float] {
        guard frame.count == Self.frameSize else {
            throw RNNoiseProcessorError.invalidFrameSize(frame.count)
        }
        let input = frame.map { $0 * 32_768 }
        var output = [Float](repeating: 0, count: Self.frameSize)
        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                _ = rnnoise_process_frame(state, outputBuffer.baseAddress, inputBuffer.baseAddress)
            }
        }
        return output.map { max(-1, min(1, $0 / 32_768)) }
    }
}

/// Converts arbitrary chunks into RNNoise's 10 ms frames and returns an
/// 80% denoised / 20% dry signal. RNNoise emits the preceding frame, so the
/// dry signal is delayed by one frame to keep both components aligned.
public final class RNNoiseStreamProcessor {
    public static let sampleRate = RNNoiseFrameProcessor.sampleRate
    public static let frameSize = RNNoiseFrameProcessor.frameSize

    private let wetMix: Float
    private let frameProcessor: RNNoiseFrameProcessor
    private var bufferedInput: [Float] = []
    private var pendingDryFrame: [Float]?
    private var pendingDryCount = 0

    public init(wetMix: Float = 0.8) throws {
        self.wetMix = max(0, min(1, wetMix))
        frameProcessor = try RNNoiseFrameProcessor()
    }

    public func process(samples: [Float]) throws -> [Float] {
        bufferedInput.append(contentsOf: samples)
        var output: [Float] = []
        while bufferedInput.count >= Self.frameSize {
            let frame = Array(bufferedInput.prefix(Self.frameSize))
            bufferedInput.removeFirst(Self.frameSize)
            output.append(contentsOf: try processCompleteFrame(frame, validCount: Self.frameSize))
        }
        return output
    }

    public func flush() throws -> [Float] {
        var output: [Float] = []
        if !bufferedInput.isEmpty {
            let validCount = bufferedInput.count
            let paddedFrame = bufferedInput + [Float](repeating: 0, count: Self.frameSize - validCount)
            output.append(contentsOf: try processCompleteFrame(paddedFrame, validCount: validCount))
            bufferedInput.removeAll(keepingCapacity: false)
        }
        if let dry = pendingDryFrame {
            let denoised = try frameProcessor.process(frame: [Float](repeating: 0, count: Self.frameSize))
            output.append(contentsOf: mix(denoised: denoised, dry: dry, count: pendingDryCount))
        }
        pendingDryFrame = nil
        pendingDryCount = 0
        return output
    }

    private func processCompleteFrame(_ frame: [Float], validCount: Int) throws -> [Float] {
        let denoised = try frameProcessor.process(frame: frame)
        var output: [Float] = []
        if let dry = pendingDryFrame {
            output = mix(denoised: denoised, dry: dry, count: pendingDryCount)
        }
        pendingDryFrame = frame
        pendingDryCount = validCount
        return output
    }

    private func mix(denoised: [Float], dry: [Float], count: Int) -> [Float] {
        let dryMix = 1 - wetMix
        return (0..<count).map { index in
            max(-1, min(1, denoised[index] * wetMix + dry[index] * dryMix))
        }
    }
}
