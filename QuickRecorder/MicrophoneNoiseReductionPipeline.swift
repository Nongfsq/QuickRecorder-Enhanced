import AVFoundation
import RNNoiseProcessor

final class MicrophoneNoiseReductionPipeline {
    static let outputSampleRate = 48_000
    static let outputChannelCount = 1

    private let lock = NSLock()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(outputSampleRate),
        channels: AVAudioChannelCount(outputChannelCount),
        interleaved: false
    )!
    private let processor: RNNoiseStreamProcessor
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var nextPresentationTimeStamp: CMTime?

    init() throws {
        processor = try RNNoiseStreamProcessor(wetMix: 0.8)
    }

    func process(_ input: AVAudioPCMBuffer, presentationTimeStamp: CMTime) throws -> [CMSampleBuffer] {
        lock.lock()
        defer { lock.unlock() }

        guard let converted = convertToRNNoiseFormat(input),
              let channel = converted.floatChannelData?[0] else { return [] }
        if nextPresentationTimeStamp == nil {
            nextPresentationTimeStamp = presentationTimeStamp
        }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
        return makeSampleBuffers(from: try processor.process(samples: samples))
    }

    func flush() throws -> [CMSampleBuffer] {
        lock.lock()
        defer { lock.unlock() }
        return makeSampleBuffers(from: try processor.flush())
    }

    private func convertToRNNoiseFormat(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if input.format == targetFormat { return input }
        if converter == nil || converterInputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: targetFormat)
            converterInputFormat = input.format
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return input
        }
        if status == .error {
            print("RNNoise input conversion failed: \(conversionError?.localizedDescription ?? "unknown error")")
            return nil
        }
        return output
    }

    private func makeSampleBuffers(from samples: [Float]) -> [CMSampleBuffer] {
        guard !samples.isEmpty,
              let presentationTimeStamp = nextPresentationTimeStamp,
              let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = output.floatChannelData?[0] else { return [] }

        output.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        nextPresentationTimeStamp = CMTimeAdd(
            presentationTimeStamp,
            CMTime(value: CMTimeValue(samples.count), timescale: CMTimeScale(Self.outputSampleRate))
        )
        guard let sampleBuffer = output.makeSampleBuffer(presentationTimeStamp: presentationTimeStamp) else { return [] }
        return [sampleBuffer]
    }
}

extension SCContext {
    static func configureMicrophoneNoiseReduction() {
        microphoneNoiseReductionPipeline = nil
        guard ud.bool(forKey: "microphoneNoiseReduction") else { return }
        do {
            microphoneNoiseReductionPipeline = try MicrophoneNoiseReductionPipeline()
            print("RNNoise microphone reduction enabled (80% processed / 20% dry)")
        } catch {
            print("Unable to initialize RNNoise; recording unprocessed microphone audio: \(error)")
        }
    }

    static func appendMicrophoneAudio(_ buffer: AVAudioPCMBuffer, presentationTimeStamp: CMTime? = nil) {
        guard micInput?.isReadyForMoreMediaData == true else { return }
        if let pipeline = microphoneNoiseReductionPipeline {
            let pts = presentationTimeStamp ?? CMClockGetTime(CMClockGetHostTimeClock())
            do {
                for sampleBuffer in try pipeline.process(buffer, presentationTimeStamp: pts) {
                    if micInput.isReadyForMoreMediaData { micInput.append(sampleBuffer) }
                }
            } catch {
                print("RNNoise processing failed: \(error)")
            }
        } else if let sampleBuffer = makeAudioSampleBufferForConfiguredChannels(buffer, presentationTimeStamp: presentationTimeStamp) {
            micInput.append(sampleBuffer)
        }
    }

    static func appendMicrophoneAudio(_ sampleBuffer: CMSampleBuffer) {
        guard micInput?.isReadyForMoreMediaData == true else { return }
        if microphoneNoiseReductionPipeline != nil, let pcmBuffer = sampleBuffer.asPCMBuffer {
            appendMicrophoneAudio(pcmBuffer, presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        } else if let converted = makeAudioSampleBufferForConfiguredChannels(sampleBuffer) {
            micInput.append(converted)
        }
    }

    static func flushMicrophoneNoiseReduction() {
        guard let pipeline = microphoneNoiseReductionPipeline else { return }
        do {
            for sampleBuffer in try pipeline.flush() {
                if micInput?.isReadyForMoreMediaData == true { micInput.append(sampleBuffer) }
            }
        } catch {
            print("Unable to flush RNNoise microphone audio: \(error)")
        }
        microphoneNoiseReductionPipeline = nil
    }
}
