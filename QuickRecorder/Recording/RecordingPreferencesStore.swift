import Foundation

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
        guard let mode = StreamType(legacyCaptureType: legacyCaptureType),
              let outputDirectory = defaults.string(forKey: "saveDirectory") else { return nil }
        return RecordingRequest(
            mode: mode,
            settings: snapshot(outputDirectory: outputDirectory),
            fastStart: fastStart
        )
    }

    func snapshot(outputDirectory: String) -> RecordingSettingsSnapshot {
        RecordingSettingsSnapshot(
            outputDirectory: outputDirectory,
            frameRate: defaults.integer(forKey: "frameRate"),
            resolutionScale: defaults.integer(forKey: "highRes"),
            videoQuality: defaults.double(forKey: "videoQuality"),
            videoBitrate: enumValue("videoBitrate", fallback: .auto),
            adaptiveVFR: defaults.bool(forKey: "adaptiveVFR"),
            videoFormat: enumValue("videoFormat", fallback: .mp4),
            pixelFormat: enumValue("pixelFormat", fallback: .delault),
            encoder: enumValue("encoder", fallback: .h264),
            recordHDR: defaults.bool(forKey: "recordHDR"),
            withAlpha: defaults.bool(forKey: "withAlpha"),
            audioFormat: enumValue("audioFormat", fallback: .aac),
            audioQuality: enumValue("audioQuality", fallback: .high),
            audioChannels: enumValue("audioChannels", fallback: .stereo),
            recordsMicrophone: defaults.bool(forKey: "recordMic"),
            recordsSystemAudio: defaults.bool(forKey: "recordWinSound"),
            remuxesAudio: defaults.bool(forKey: "remuxAudio"),
            microphoneDevice: defaults.string(forKey: "micDevice") ?? "default",
            enablesAEC: defaults.bool(forKey: "enableAEC"),
            microphoneNoiseReduction: defaults.bool(forKey: "microphoneNoiseReduction"),
            aecLevel: defaults.string(forKey: "AECLevel") ?? "mid",
            background: enumValue("background", fallback: .wallpaper),
            showsMouse: defaults.bool(forKey: "showMouse"),
            highlightsMouse: defaults.bool(forKey: "highlightMouse"),
            includesMenuBar: defaults.bool(forKey: "includeMenuBar"),
            hidesDesktopFiles: defaults.bool(forKey: "hideDesktopFiles"),
            hidesSelf: defaults.bool(forKey: "hideSelf"),
            hidesControlCenter: defaults.bool(forKey: "hideCCenter"),
            preventsSleep: defaults.bool(forKey: "preventSleep"),
            showsPreview: defaults.bool(forKey: "showPreview"),
            trimsAfterRecording: defaults.bool(forKey: "trimAfterRecord"),
            presenterOverlaySafeDelay: defaults.integer(forKey: "poSafeDelay")
        )
    }

    private func enumValue<T: RawRepresentable>(_ key: String, fallback: T) -> T where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }

    private func enumValue<T: RawRepresentable>(_ key: String, fallback: T) -> T where T.RawValue == Int {
        T(rawValue: defaults.integer(forKey: key)) ?? fallback
    }
}
