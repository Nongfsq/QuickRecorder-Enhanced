import Foundation

public struct RecordingSettingsSnapshot: Equatable, Codable, Sendable {
    public var outputDirectory: String
    public var frameRate: Int
    public var resolutionScale: Int
    public var videoQuality: Double
    public var videoBitrate: VideoBitrate
    public var adaptiveVFR: Bool
    public var videoFormat: VideoFormat
    public var pixelFormat: PixFormat
    public var encoder: Encoder
    public var recordHDR: Bool
    public var withAlpha: Bool
    public var audioFormat: AudioFormat
    public var audioQuality: AudioQuality
    public var audioChannels: AudioChannels
    public var recordsMicrophone: Bool
    public var recordsSystemAudio: Bool
    public var remuxesAudio: Bool
    public var microphoneDevice: String
    public var enablesAEC: Bool
    public var microphoneNoiseReduction: Bool
    public var aecLevel: String
    public var background: BackgroundType
    public var showsMouse: Bool
    public var highlightsMouse: Bool
    public var includesMenuBar: Bool
    public var hidesDesktopFiles: Bool
    public var hidesSelf: Bool
    public var hidesControlCenter: Bool
    public var preventsSleep: Bool
    public var showsPreview: Bool
    public var trimsAfterRecording: Bool
    public var presenterOverlaySafeDelay: Int

    public init(
        outputDirectory: String,
        frameRate: Int,
        resolutionScale: Int,
        videoQuality: Double,
        videoBitrate: VideoBitrate,
        adaptiveVFR: Bool,
        videoFormat: VideoFormat,
        pixelFormat: PixFormat,
        encoder: Encoder,
        recordHDR: Bool,
        withAlpha: Bool,
        audioFormat: AudioFormat,
        audioQuality: AudioQuality,
        audioChannels: AudioChannels,
        recordsMicrophone: Bool,
        recordsSystemAudio: Bool,
        remuxesAudio: Bool,
        microphoneDevice: String,
        enablesAEC: Bool,
        microphoneNoiseReduction: Bool,
        aecLevel: String,
        background: BackgroundType,
        showsMouse: Bool,
        highlightsMouse: Bool,
        includesMenuBar: Bool,
        hidesDesktopFiles: Bool,
        hidesSelf: Bool,
        hidesControlCenter: Bool,
        preventsSleep: Bool,
        showsPreview: Bool,
        trimsAfterRecording: Bool,
        presenterOverlaySafeDelay: Int
    ) {
        self.outputDirectory = outputDirectory
        self.frameRate = min(240, max(1, frameRate))
        self.resolutionScale = resolutionScale == 1 ? 1 : 2
        self.videoQuality = Self.normalizedVideoQuality(videoQuality)
        self.videoBitrate = videoBitrate
        self.adaptiveVFR = adaptiveVFR
        self.videoFormat = videoFormat
        self.pixelFormat = pixelFormat
        self.encoder = encoder
        self.recordHDR = recordHDR
        self.withAlpha = withAlpha && !recordHDR
        self.audioFormat = audioFormat
        self.audioQuality = audioQuality
        self.audioChannels = audioChannels
        self.recordsMicrophone = recordsMicrophone
        self.recordsSystemAudio = recordsSystemAudio
        self.remuxesAudio = remuxesAudio
        self.microphoneDevice = microphoneDevice.isEmpty ? "default" : microphoneDevice
        self.microphoneNoiseReduction = microphoneNoiseReduction
        self.enablesAEC = enablesAEC && !microphoneNoiseReduction
        self.aecLevel = ["min", "mid", "max"].contains(aecLevel) ? aecLevel : "mid"
        self.background = recordHDR && background == .clear ? .wallpaper : background
        self.showsMouse = showsMouse
        self.highlightsMouse = highlightsMouse
        self.includesMenuBar = includesMenuBar
        self.hidesDesktopFiles = hidesDesktopFiles
        self.hidesSelf = hidesSelf
        self.hidesControlCenter = hidesControlCenter
        self.preventsSleep = preventsSleep
        self.showsPreview = showsPreview
        self.trimsAfterRecording = trimsAfterRecording
        self.presenterOverlaySafeDelay = min(10, max(0, presenterOverlaySafeDelay))
    }

    private static func normalizedVideoQuality(_ value: Double) -> Double {
        let supported = [0.3, 0.7, 1.0]
        return supported.min(by: { abs($0 - value) < abs($1 - value) }) ?? 1.0
    }
}

public struct RecordingRequest: Equatable, Codable, Sendable {
    public let id: UUID
    public let mode: StreamType
    public let settings: RecordingSettingsSnapshot
    public let fastStart: Bool

    public init(
        id: UUID = UUID(),
        mode: StreamType,
        settings: RecordingSettingsSnapshot,
        fastStart: Bool
    ) {
        self.id = id
        self.mode = mode
        self.settings = settings
        self.fastStart = fastStart
    }
}

public extension StreamType {
    init?(legacyCaptureType: String) {
        switch legacyCaptureType {
        case "window": self = .window
        case "windows": self = .windows
        case "display": self = .screen
        case "application": self = .application
        case "area": self = .screenarea
        case "audio": self = .systemaudio
        default: return nil
        }
    }
}
