import Foundation

public struct VideoEncodingPolicyInput: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var frameRate: Int
    public var encoder: Encoder
    public var recordsHDR: Bool
    public var quality: Double
    public var configuredBitrateKbps: Int
    public var adaptiveVFR: Bool

    public init(
        width: Int,
        height: Int,
        frameRate: Int,
        encoder: Encoder,
        recordsHDR: Bool,
        quality: Double,
        configuredBitrateKbps: Int,
        adaptiveVFR: Bool
    ) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.encoder = encoder
        self.recordsHDR = recordsHDR
        self.quality = quality
        self.configuredBitrateKbps = configuredBitrateKbps
        self.adaptiveVFR = adaptiveVFR
    }
}

public struct VideoEncodingPolicyOutput: Equatable, Sendable {
    public let targetBitrate: Double
    public let averageBitrate: Int
    public let maxKeyFrameIntervalDuration: Int

    public init(targetBitrate: Double, averageBitrate: Int, maxKeyFrameIntervalDuration: Int) {
        self.targetBitrate = targetBitrate
        self.averageBitrate = averageBitrate
        self.maxKeyFrameIntervalDuration = maxKeyFrameIntervalDuration
    }
}

public enum VideoEncodingPolicy {
    public static func evaluate(_ input: VideoEncodingPolicyInput) -> VideoEncodingPolicyOutput {
        let frameRate = min(240, max(1, input.frameRate))
        let fpsMultiplier = Double(frameRate) / 8
        let encoderMultiplier = (input.encoder == .h265 || input.recordsHDR) ? 0.5 : 0.9
        let resolution = Double(max(600, input.width)) * Double(max(600, input.height))
        var qualityMultiplier = 1 - (log10(sqrt(resolution) * fpsMultiplier) / 5)

        switch input.quality {
        case 0.3:
            qualityMultiplier = max(0.1, qualityMultiplier)
        case 0.7:
            qualityMultiplier = max(0.4, min(0.6, qualityMultiplier * 3))
        default:
            qualityMultiplier = 1.0
        }

        let target = resolution
            * fpsMultiplier
            * encoderMultiplier
            * qualityMultiplier
            * (input.recordsHDR ? 2 : 1)
        let configured = max(0, input.configuredBitrateKbps) * 1_000

        return VideoEncodingPolicyOutput(
            targetBitrate: target,
            averageBitrate: configured > 0 ? configured : max(200_000, Int(target)),
            maxKeyFrameIntervalDuration: input.adaptiveVFR ? 18 : 2
        )
    }
}

public struct AdaptiveVFRInput: Equatable, Sendable {
    public var enabled: Bool
    public var recordsHDR: Bool
    public var hasFirstFrame: Bool
    public var previousVideoTime: TimeInterval?
    public var currentVideoTime: TimeInterval
    public var dirtyArea: Double
    public var frameRate: Int
    public var idleKeepAliveInterval: TimeInterval

    public init(
        enabled: Bool,
        recordsHDR: Bool,
        hasFirstFrame: Bool,
        previousVideoTime: TimeInterval?,
        currentVideoTime: TimeInterval,
        dirtyArea: Double,
        frameRate: Int,
        idleKeepAliveInterval: TimeInterval = 5
    ) {
        self.enabled = enabled
        self.recordsHDR = recordsHDR
        self.hasFirstFrame = hasFirstFrame
        self.previousVideoTime = previousVideoTime
        self.currentVideoTime = currentVideoTime
        self.dirtyArea = dirtyArea
        self.frameRate = frameRate
        self.idleKeepAliveInterval = idleKeepAliveInterval
    }
}

public enum AdaptiveVFRPolicy {
    public static func shouldSkip(_ input: AdaptiveVFRInput) -> Bool {
        guard input.enabled, !input.recordsHDR, input.hasFirstFrame,
              let previous = input.previousVideoTime else { return false }

        let elapsed = input.currentVideoTime - previous
        guard elapsed >= 0 else { return false }
        let maximumFPSInterval = 1.0 / Double(max(1, input.frameRate))
        if elapsed < maximumFPSInterval * 0.9 { return true }
        if input.dirtyArea > 0 { return false }
        if elapsed >= input.idleKeepAliveInterval { return false }
        return true
    }
}

public struct CaptureDimensionSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct CaptureDimensionPolicyInput: Equatable, Sendable {
    public var mode: StreamType
    public var modernFilterSize: CaptureDimensionSize?
    public var legacyDisplaySize: CaptureDimensionSize?
    public var legacyWindowSize: CaptureDimensionSize?
    public var selectedAreaSize: CaptureDimensionSize?
    public var pointPixelScale: Double
    public var resolutionScale: Int

    public init(
        mode: StreamType,
        modernFilterSize: CaptureDimensionSize? = nil,
        legacyDisplaySize: CaptureDimensionSize? = nil,
        legacyWindowSize: CaptureDimensionSize? = nil,
        selectedAreaSize: CaptureDimensionSize? = nil,
        pointPixelScale: Double,
        resolutionScale: Int
    ) {
        self.mode = mode
        self.modernFilterSize = modernFilterSize
        self.legacyDisplaySize = legacyDisplaySize
        self.legacyWindowSize = legacyWindowSize
        self.selectedAreaSize = selectedAreaSize
        self.pointPixelScale = pointPixelScale
        self.resolutionScale = resolutionScale
    }
}

public struct CaptureDimensions: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum CaptureDimensionPolicy {
    public static func evaluate(_ input: CaptureDimensionPolicyInput) -> CaptureDimensions? {
        if input.mode == .systemaudio {
            return CaptureDimensions(width: 2, height: 2)
        }

        let logicalSize: CaptureDimensionSize?
        if input.mode == .screenarea, let area = input.selectedAreaSize {
            logicalSize = area
        } else if let modern = input.modernFilterSize {
            logicalSize = modern
        } else if input.mode == .window {
            logicalSize = input.legacyWindowSize
        } else {
            logicalSize = input.legacyDisplaySize
        }

        guard let logicalSize,
              logicalSize.width.isFinite, logicalSize.height.isFinite,
              logicalSize.width > 0, logicalSize.height > 0 else { return nil }
        let pixelMultiplier = input.resolutionScale == 2 ? max(1, input.pointPixelScale) : 1
        return CaptureDimensions(
            width: max(2, Int(logicalSize.width * pixelMultiplier)),
            height: max(2, Int(logicalSize.height * pixelMultiplier))
        )
    }
}

public struct AudioRenderTrackDuration: Equatable, Sendable {
    public var frameCount: Int64
    public var sampleRate: Double

    public init(frameCount: Int64, sampleRate: Double) {
        self.frameCount = frameCount
        self.sampleRate = sampleRate
    }
}

public enum AudioRenderDurationPolicy {
    public static func targetFrameCount(
        tracks: [AudioRenderTrackDuration],
        outputSampleRate: Double
    ) -> Int64? {
        guard outputSampleRate.isFinite, outputSampleRate > 0 else { return nil }
        var maximumDuration: Double = 0
        for track in tracks {
            guard track.frameCount >= 0, track.sampleRate.isFinite, track.sampleRate > 0 else { return nil }
            maximumDuration = max(maximumDuration, Double(track.frameCount) / track.sampleRate)
        }
        let target = ceil(maximumDuration * outputSampleRate)
        guard target.isFinite, target <= Double(Int64.max) else { return nil }
        return Int64(target)
    }
}

public struct PauseTimeline: Equatable, Sendable {
    public private(set) var accumulatedOffset: TimeInterval
    public private(set) var lastEmittedTime: TimeInterval?
    public private(set) var isPaused: Bool
    private var awaitingResumeSample: Bool

    public init(
        accumulatedOffset: TimeInterval = 0,
        lastEmittedTime: TimeInterval? = nil,
        isPaused: Bool = false
    ) {
        self.accumulatedOffset = max(0, accumulatedOffset)
        self.lastEmittedTime = lastEmittedTime
        self.isPaused = isPaused
        self.awaitingResumeSample = false
    }

    public mutating func pause() {
        isPaused = true
    }

    public mutating func resume() {
        guard isPaused else { return }
        isPaused = false
        awaitingResumeSample = true
    }

    public mutating func adjustedTime(
        for sourceTime: TimeInterval,
        minimumStep: TimeInterval = 0.000_000_001
    ) -> TimeInterval? {
        guard sourceTime.isFinite, !isPaused else { return nil }
        let minimumStep = minimumStep.isFinite ? max(0.000_000_001, minimumStep) : 0.000_000_001

        if awaitingResumeSample, let lastEmittedTime {
            let nextTime = lastEmittedTime + minimumStep
            accumulatedOffset = max(0, sourceTime - nextTime)
            awaitingResumeSample = false
        }

        let adjusted = sourceTime - accumulatedOffset
        guard lastEmittedTime.map({ adjusted > $0 }) ?? true else { return nil }
        lastEmittedTime = adjusted
        return adjusted
    }
}
