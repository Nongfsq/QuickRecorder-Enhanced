import Foundation
import RecordingDomain

struct RecordingPreferencesStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func registeredDefaults(outputDirectory: String, isMacOS12: Bool) -> [String: Any] {
        [
            "audioFormat": AudioFormat.aac.rawValue,
            "audioQuality": AudioQuality.high.rawValue,
            "audioChannels": AudioChannels.stereo.rawValue,
            "background": BackgroundType.wallpaper.rawValue,
            "frameRate": 60,
            "highRes": 2,
            "hideSelf": true,
            "highlightMouse": false,
            "hideDesktopFiles": false,
            "includeMenuBar": true,
            "hideCCenter": false,
            "videoBitrate": VideoBitrate.auto.rawValue,
            "adaptiveVFR": false,
            "videoQuality": 1.0,
            "videoFormat": VideoFormat.mp4.rawValue,
            "pixelFormat": PixFormat.delault.rawValue,
            "encoder": Encoder.h264.rawValue,
            "recordHDR": false,
            "withAlpha": false,
            "poSafeDelay": 1,
            "saveDirectory": outputDirectory as NSString,
            "showMouse": true,
            "recordMic": false,
            "recordWinSound": !isMacOS12,
            "remuxAudio": !isMacOS12,
            "micDevice": "default",
            "enableAEC": false,
            "microphoneNoiseReduction": false,
            "AECLevel": "mid",
            "trimAfterRecord": false,
            "preventSleep": true,
            "showPreview": !isMacOS12
        ]
    }

    func makeRequest(legacyCaptureType: String, fastStart: Bool) -> RecordingRequest? {
        RecordingSettingsDefaultsAdapter(defaults: defaults).makeRequest(
            legacyCaptureType: legacyCaptureType,
            fastStart: fastStart
        )
    }

    func makeRequest(mode: StreamType, fastStart: Bool = false) -> RecordingRequest? {
        RecordingSettingsDefaultsAdapter(defaults: defaults).makeRequest(mode: mode, fastStart: fastStart)
    }

    func snapshot(outputDirectory: String) -> RecordingSettingsSnapshot {
        RecordingSettingsDefaultsAdapter(defaults: defaults).snapshot(outputDirectory: outputDirectory)
    }
}
