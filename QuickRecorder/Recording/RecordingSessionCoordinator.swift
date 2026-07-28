import AppKit
import AVFoundation
import Foundation
import RecordingDomain
import ScreenCaptureKit

/// Session-scoped capture resources. `SCContext` keeps compatibility accessors
/// while call sites are migrated, but no longer owns this mutable storage.
private final class RecordingOwnerIsolation {
    private let lock = NSLock()

    func sync<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

final class RecordingCaptureContextOwner {
    private let isolation = RecordingOwnerIsolation()
    private var filterStorage: SCContentFilter?
    private var streamStorage: SCStream?
    private var screenStorage: SCDisplay?
    private var windowsStorage: [SCWindow]?
    private var applicationsStorage: [SCRunningApplication]?
    private var modeStorage: StreamType?
    private var screenAreaStorage: NSRect?
    private var availableContentStorage: SCShareableContent?

    var filter: SCContentFilter? { get { isolation.sync { filterStorage } } set { isolation.sync { filterStorage = newValue } } }
    var stream: SCStream? { get { isolation.sync { streamStorage } } set { isolation.sync { streamStorage = newValue } } }
    var screen: SCDisplay? { get { isolation.sync { screenStorage } } set { isolation.sync { screenStorage = newValue } } }
    var windows: [SCWindow]? { get { isolation.sync { windowsStorage } } set { isolation.sync { windowsStorage = newValue } } }
    var applications: [SCRunningApplication]? { get { isolation.sync { applicationsStorage } } set { isolation.sync { applicationsStorage = newValue } } }
    var mode: StreamType? { get { isolation.sync { modeStorage } } set { isolation.sync { modeStorage = newValue } } }
    var screenArea: NSRect? { get { isolation.sync { screenAreaStorage } } set { isolation.sync { screenAreaStorage = newValue } } }
    var availableContent: SCShareableContent? { get { isolation.sync { availableContentStorage } } set { isolation.sync { availableContentStorage = newValue } } }
}

final class RecordingDeviceContextOwner {
    private let isolation = RecordingOwnerIsolation()
    private var captureSessionStorage: AVCaptureSession?
    private var previewSessionStorage: AVCaptureSession?
    private var frameCacheStorage: CMSampleBuffer?
    private var cameraIdentifierStorage = ""
    private var deviceIdentifierStorage = ""

    var captureSession: AVCaptureSession? { get { isolation.sync { captureSessionStorage } } set { isolation.sync { captureSessionStorage = newValue } } }
    var previewSession: AVCaptureSession? { get { isolation.sync { previewSessionStorage } } set { isolation.sync { previewSessionStorage = newValue } } }
    var frameCache: CMSampleBuffer? { get { isolation.sync { frameCacheStorage } } set { isolation.sync { frameCacheStorage = newValue } } }
    var cameraIdentifier: String { get { isolation.sync { cameraIdentifierStorage } } set { isolation.sync { cameraIdentifierStorage = newValue } } }
    var deviceIdentifier: String { get { isolation.sync { deviceIdentifierStorage } } set { isolation.sync { deviceIdentifierStorage = newValue } } }
}

final class RecordingFinalizationContextOwner {
    private let isolation = RecordingOwnerIsolation()
    private var trimmingListStorage = [URL]()
    private var primaryPathStorage: String?
    private var systemAudioPathStorage: String?
    private var microphonePathStorage: String?
    private var systemAudioFileStorage: AVAudioFile?
    private var microphoneAudioFileStorage: AVAudioFile?
    private var elapsedTimeStorage: TimeInterval = 0
    private var partialPackagePathStorage: String?

    var trimmingList: [URL] { get { isolation.sync { trimmingListStorage } } set { isolation.sync { trimmingListStorage = newValue } } }
    var primaryPath: String? { get { isolation.sync { primaryPathStorage } } set { isolation.sync { primaryPathStorage = newValue } } }
    var systemAudioPath: String? { get { isolation.sync { systemAudioPathStorage } } set { isolation.sync { systemAudioPathStorage = newValue } } }
    var microphonePath: String? { get { isolation.sync { microphonePathStorage } } set { isolation.sync { microphonePathStorage = newValue } } }
    var systemAudioFile: AVAudioFile? { get { isolation.sync { systemAudioFileStorage } } set { isolation.sync { systemAudioFileStorage = newValue } } }
    var microphoneAudioFile: AVAudioFile? { get { isolation.sync { microphoneAudioFileStorage } } set { isolation.sync { microphoneAudioFileStorage = newValue } } }
    var elapsedTime: TimeInterval { get { isolation.sync { elapsedTimeStorage } } set { isolation.sync { elapsedTimeStorage = newValue } } }
    var partialPackagePath: String? { get { isolation.sync { partialPackagePathStorage } } set { isolation.sync { partialPackagePathStorage = newValue } } }
}

final class RecordingSessionMediaOwner: @unchecked Sendable {
    struct WriterResult {
        let status: AVAssetWriter.Status
        let error: Error?
    }

    private let queue = DispatchQueue(label: "com.nongfsq.QuickRecorder.recording-media")
    private let queueKey = DispatchSpecificKey<Void>()

    private var writerStorage: AVAssetWriter?
    private var videoInputStorage: AVAssetWriterInput?
    private var systemAudioInputStorage: AVAssetWriterInput?
    private var microphoneInputStorage: AVAssetWriterInput?
    private var acceptsSamples = false

    private var firstFrameStorage: CMSampleBuffer?
    private var lastPTSStorage: CMTime?
    private var lastVideoPTSStorage: CMTime?
    private var pausedStorage = false
    private var startTimeStorage: Date?
    private var adaptiveVFRSkippedFramesStorage = 0
    private var videoPauseTimeline = PauseTimeline()
    private var audioPauseTimeline = PauseTimeline()
    private var microphonePauseTimeline = PauseTimeline()

    init() {
        queue.setSpecific(key: queueKey, value: ())
    }

    func resetTimeline() {
        sync {
            firstFrameStorage = nil
            lastPTSStorage = nil
            lastVideoPTSStorage = nil
            pausedStorage = false
            startTimeStorage = nil
            adaptiveVFRSkippedFramesStorage = 0
            videoPauseTimeline = PauseTimeline()
            audioPauseTimeline = PauseTimeline()
            microphonePauseTimeline = PauseTimeline()
            acceptsSamples = false
        }
    }

    func startAcceptingSamplesWithoutWriter() {
        sync { acceptsSamples = true }
    }

    @discardableResult
    func installWriter(
        _ writer: AVAssetWriter,
        videoInput: AVAssetWriterInput? = nil,
        systemAudioInput: AVAssetWriterInput? = nil,
        microphoneInput: AVAssetWriterInput? = nil
    ) -> Bool {
        sync {
            guard videoInput.map({ writer.canAdd($0) }) ?? true,
                  systemAudioInput.map({ writer.canAdd($0) }) ?? true,
                  microphoneInput.map({ writer.canAdd($0) }) ?? true else {
                acceptsSamples = false
                return false
            }
            writerStorage = writer
            videoInputStorage = videoInput
            systemAudioInputStorage = systemAudioInput
            microphoneInputStorage = microphoneInput
            if let videoInput { writer.add(videoInput) }
            if let systemAudioInput { writer.add(systemAudioInput) }
            if let microphoneInput { writer.add(microphoneInput) }
            acceptsSamples = writer.startWriting()
            return acceptsSamples
        }
    }

    func enqueueSample(_ operation: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self = self, self.acceptsSamples else { return }
            operation()
        }
    }

    func performSample(_ operation: () -> Void) {
        sync {
            guard acceptsSamples else { return }
            operation()
        }
    }

    func stopAcceptingSamples() {
        sync { acceptsSamples = false }
    }

    func finishWriting(
        markVideoInput: Bool,
        markSystemAudioInput: Bool,
        markMicrophoneInput: Bool
    ) async -> WriterResult? {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                self.acceptsSamples = false
                if markMicrophoneInput { self.microphoneInputStorage?.markAsFinished() }
                if markVideoInput { self.videoInputStorage?.markAsFinished() }
                if markSystemAudioInput { self.systemAudioInputStorage?.markAsFinished() }
                guard let writer = self.writerStorage else {
                    continuation.resume(returning: nil)
                    return
                }
                writer.finishWriting { [weak self] in
                    guard let self else {
                        continuation.resume(returning: WriterResult(status: writer.status, error: writer.error))
                        return
                    }
                    self.queue.async {
                        continuation.resume(returning: WriterResult(status: writer.status, error: writer.error))
                    }
                }
            }
        }
    }

    func togglePaused() -> Bool {
        sync {
            pausedStorage.toggle()
            if pausedStorage {
                videoPauseTimeline.pause()
                audioPauseTimeline.pause()
                microphonePauseTimeline.pause()
            } else {
                videoPauseTimeline.resume()
                audioPauseTimeline.resume()
                microphonePauseTimeline.resume()
            }
            return pausedStorage
        }
    }

    func adjustedSampleForPause(_ sample: CMSampleBuffer, isVideo: Bool) -> CMSampleBuffer? {
        assertIsolated()
        let sourceTime = CMSampleBufferGetPresentationTimeStamp(sample)
        let sourceTick = sourceTime.timescale > 0 ? 1 / Double(sourceTime.timescale) : 0.000_000_001
        let sampleStep = CMTimeGetSeconds(Self.sampleDuration(of: sample))
        let minimumStep = sampleStep.isFinite && sampleStep > 0 ? max(sampleStep, sourceTick) : sourceTick
        let adjustedSeconds: TimeInterval?
        if isVideo {
            adjustedSeconds = videoPauseTimeline.adjustedTime(
                for: CMTimeGetSeconds(sourceTime),
                minimumStep: minimumStep
            )
        } else {
            adjustedSeconds = audioPauseTimeline.adjustedTime(
                for: CMTimeGetSeconds(sourceTime),
                minimumStep: minimumStep
            )
        }
        guard let adjustedSeconds else { return nil }
        let adjustedTime = CMTime(seconds: adjustedSeconds, preferredTimescale: max(1, sourceTime.timescale))
        let offset = CMTimeSubtract(sourceTime, adjustedTime)
        guard CMTimeCompare(offset, .zero) > 0 else { return sample }
        return Self.adjustTime(sample: sample, by: offset)
    }

    func adjustedMicrophoneTime(
        sourceTime: CMTime,
        sampleDuration: CMTime
    ) -> CMTime? {
        assertIsolated()
        let sourceTick = sourceTime.timescale > 0 ? 1 / Double(sourceTime.timescale) : 0.000_000_001
        let sampleStep = CMTimeGetSeconds(sampleDuration)
        let duration = sampleStep.isFinite && sampleStep > 0 ? max(sampleStep, sourceTick) : sourceTick
        guard let adjustedSeconds = microphonePauseTimeline.adjustedTime(
            for: CMTimeGetSeconds(sourceTime),
            minimumStep: duration
        ) else { return nil }
        return CMTime(seconds: adjustedSeconds, preferredTimescale: max(1, sourceTime.timescale))
    }

    func adjustedMicrophoneSampleForPause(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        assertIsolated()
        let sourceTime = CMSampleBufferGetPresentationTimeStamp(sample)
        let duration = Self.sampleDuration(of: sample)
        guard let adjustedTime = adjustedMicrophoneTime(
            sourceTime: sourceTime,
            sampleDuration: duration
        ) else { return nil }
        let offset = CMTimeSubtract(sourceTime, adjustedTime)
        guard CMTimeCompare(offset, .zero) > 0 else { return sample }
        return Self.adjustTime(sample: sample, by: offset)
    }

    private static func sampleDuration(of sample: CMSampleBuffer) -> CMTime {
        let duration = CMSampleBufferGetDuration(sample)
        if duration.isValid, CMTimeCompare(duration, .zero) > 0 { return duration }
        let sampleRate = sample.formatDescription?.audioStreamBasicDescription?.mSampleRate ?? 0
        guard sampleRate.isFinite, sampleRate > 0 else {
            return CMTime(value: 1, timescale: 1_000_000_000)
        }
        return CMTime(
            value: CMTimeValue(CMSampleBufferGetNumSamples(sample)),
            timescale: CMTimeScale(sampleRate.rounded())
        )
    }

    private static func adjustTime(sample: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        guard CMSampleBufferGetFormatDescription(sample) != nil else { return nil }
        var timingInfo = [CMSampleTimingInfo](
            repeating: CMSampleTimingInfo(),
            count: Int(CMSampleBufferGetNumSamples(sample))
        )
        CMSampleBufferGetSampleTimingInfoArray(
            sample,
            entryCount: timingInfo.count,
            arrayToFill: &timingInfo,
            entriesNeededOut: nil
        )
        for index in timingInfo.indices {
            timingInfo[index].decodeTimeStamp = CMTimeSubtract(timingInfo[index].decodeTimeStamp, offset)
            timingInfo[index].presentationTimeStamp = CMTimeSubtract(timingInfo[index].presentationTimeStamp, offset)
        }
        var adjusted: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil,
            sampleBuffer: sample,
            sampleTimingEntryCount: timingInfo.count,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &adjusted
        )
        return adjusted
    }

    func discardWriter() {
        sync {
            acceptsSamples = false
            writerStorage = nil
            videoInputStorage = nil
            systemAudioInputStorage = nil
            microphoneInputStorage = nil
        }
    }

    func cancelWriting() {
        sync {
            acceptsSamples = false
            writerStorage?.cancelWriting()
        }
    }

    func assertIsolated() {
        dispatchPrecondition(condition: .onQueue(queue))
    }

    func sync<T>(_ operation: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return operation() }
        return queue.sync(execute: operation)
    }

    var writer: AVAssetWriter? {
        get {
            assertIsolated()
            return writerStorage
        }
    }

    var videoInput: AVAssetWriterInput? {
        get {
            assertIsolated()
            return videoInputStorage
        }
    }

    var systemAudioInput: AVAssetWriterInput? {
        get {
            assertIsolated()
            return systemAudioInputStorage
        }
    }

    var microphoneInput: AVAssetWriterInput? {
        get {
            assertIsolated()
            return microphoneInputStorage
        }
    }

    var firstFrame: CMSampleBuffer? {
        get { sync { firstFrameStorage } }
        set { sync { firstFrameStorage = newValue } }
    }

    var lastPTS: CMTime? {
        get { sync { lastPTSStorage } }
        set { sync { lastPTSStorage = newValue } }
    }

    var lastVideoPTS: CMTime? {
        get { sync { lastVideoPTSStorage } }
        set { sync { lastVideoPTSStorage = newValue } }
    }

    var isPaused: Bool {
        get { sync { pausedStorage } }
        set { sync { pausedStorage = newValue } }
    }

    var startTime: Date? {
        get { sync { startTimeStorage } }
        set { sync { startTimeStorage = newValue } }
    }

    var adaptiveVFRSkippedFrames: Int {
        get { sync { adaptiveVFRSkippedFramesStorage } }
        set { sync { adaptiveVFRSkippedFramesStorage = newValue } }
    }
}

final class RecordingSessionCoordinator {
    private let lock = NSLock()
    private var machine = RecordingSessionStateMachine()
    private var activeRequest: RecordingRequest?
    private var completionWaiters: [() -> Void] = []
    let media = RecordingSessionMediaOwner()
    let capture = RecordingCaptureContextOwner()
    let device = RecordingDeviceContextOwner()
    let finalization = RecordingFinalizationContextOwner()

    var request: RecordingRequest? {
        withLock { activeRequest }
    }

    var state: RecordingSessionState {
        withLock { machine.state }
    }

    var isActive: Bool {
        withLock { machine.state.sessionID != nil }
    }

    @discardableResult
    func prepare(_ request: RecordingRequest) -> Bool {
        withLock {
            guard machine.state == .idle else { return false }
            do {
                try machine.apply(.prepare(id: request.id))
                activeRequest = request
                return true
            } catch {
                return false
            }
        }
    }

    func markStarted(at date: Date = Date()) {
        _ = apply(.start(at: date))
    }

    func markPaused() {
        _ = apply(.pause)
    }

    func markResumed() {
        _ = apply(.resume)
    }

    @discardableResult
    func beginStopping(completion: (() -> Void)? = nil) -> Bool {
        withLock {
            if let completion {
                if machine.state.sessionID == nil {
                    DispatchQueue.main.async(execute: completion)
                } else {
                    completionWaiters.append(completion)
                }
            }
            if case .stopping = machine.state { return false }
            if case .finalizing = machine.state { return false }
            do {
                try machine.apply(.stop)
                return true
            } catch {
                reportInvalidTransition(error)
                return false
            }
        }
    }

    @discardableResult
    func beginFinalizing() -> Bool {
        withLock {
            if case .finalizing = machine.state { return true }
            do {
                try machine.apply(.beginFinalizing)
                return true
            } catch {
                reportInvalidTransition(error)
                return false
            }
        }
    }

    @discardableResult
    func finish(
        _ outcome: FinalizationOutcome,
        consumer: (RecordingRequest, FinalizationOutcome) -> Void
    ) -> Bool {
        let request: RecordingRequest? = withLock {
            guard case .finalizing = machine.state, let activeRequest else { return nil }
            do {
                switch outcome {
                case .success:
                    try machine.apply(.complete)
                case let .failure(failure):
                    try machine.apply(.fail(reason: failure.message))
                }
                return activeRequest
            } catch {
                reportInvalidTransition(error)
                return nil
            }
        }
        guard let request else { return false }

        consumer(request, outcome)
        let waiters: [() -> Void] = withLock {
            do {
                try machine.apply(.reset)
            } catch {
                reportInvalidTransition(error)
                return []
            }
            activeRequest = nil
            let waiters = completionWaiters
            completionWaiters.removeAll()
            return waiters
        }
        waiters.forEach { $0() }
        return true
    }

    func fail(_ reason: String) {
        let waiters: [() -> Void] = withLock {
            do {
                try machine.apply(.fail(reason: reason))
                try machine.apply(.reset)
            } catch {
                reportInvalidTransition(error)
                return []
            }
            activeRequest = nil
            let waiters = completionWaiters
            completionWaiters.removeAll()
            return waiters
        }
        waiters.forEach { $0() }
    }

    func whenFinalizationCompletes(_ completion: @escaping () -> Void) {
        withLock {
            guard machine.state.sessionID != nil else {
                DispatchQueue.main.async(execute: completion)
                return
            }
            completionWaiters.append(completion)
        }
    }

    @discardableResult
    private func apply(_ event: RecordingSessionEvent) -> Bool {
        withLock {
            do {
                try machine.apply(event)
                return true
            } catch {
                reportInvalidTransition(error)
                return false
            }
        }
    }

    private func reportInvalidTransition(_ error: Error) {
        assertionFailure("Invalid recording-session transition: \(error)")
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
