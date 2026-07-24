import Foundation

enum AV1ArchiveAudioMode: String, CaseIterable, Identifiable {
    case copy
    case aacMono48k = "aac-mono-48k"
    case aacMono64k = "aac-mono-64k"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .copy: return "Copy audio"
        case .aacMono48k: return "AAC mono 48 kbps"
        case .aacMono64k: return "AAC mono 64 kbps"
        }
    }

    var filenameToken: String {
        switch self {
        case .copy: return "copy"
        case .aacMono48k: return "aac48"
        case .aacMono64k: return "aac64"
        }
    }

    var ffmpegArguments: [String] {
        switch self {
        case .copy:
            return ["-c:a", "copy"]
        case .aacMono48k:
            return ["-c:a", "aac", "-ac:a", "1", "-ar:a", "48000", "-b:a", "48k"]
        case .aacMono64k:
            return ["-c:a", "aac", "-ac:a", "1", "-ar:a", "48000", "-b:a", "64k"]
        }
    }
}

struct AV1ArchivePreset {
    var crf: Int
    var svtPreset: Int
    var gop: Int
    var audioMode: AV1ArchiveAudioMode

    static var current: AV1ArchivePreset {
        let crf = boundedInt(ud.integer(forKey: "archiveAV1CRF"), defaultValue: 56, range: 0...63)
        let preset = boundedInt(ud.integer(forKey: "archiveAV1SVTPreset"), defaultValue: 8, range: 0...13)
        let gop = boundedInt(ud.integer(forKey: "archiveAV1GOP"), defaultValue: 270, range: 1...2000)
        let audioRaw = ud.string(forKey: "archiveAV1AudioMode") ?? AV1ArchiveAudioMode.aacMono64k.rawValue
        let audioMode = AV1ArchiveAudioMode(rawValue: audioRaw) ?? .aacMono64k
        return AV1ArchivePreset(crf: crf, svtPreset: preset, gop: gop, audioMode: audioMode)
    }

    var outputSuffix: String {
        ".av1-crf\(crf)-preset\(svtPreset)-\(audioMode.filenameToken)-vfr-clean.mp4"
    }

    private static func boundedInt(_ value: Int, defaultValue: Int, range: ClosedRange<Int>) -> Int {
        guard range.contains(value) else { return defaultValue }
        return value
    }
}

enum ArchiveJobStatus: String {
    case preparing
    case runtimeMissing
    case compressing
    case verifying
    case completed
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .preparing: return "Preparing"
        case .runtimeMissing: return "FFmpeg runtime missing"
        case .compressing: return "Compressing"
        case .verifying: return "Verifying"
        case .completed: return "Archive Complete"
        case .failed: return "Archive Failed"
        case .cancelled: return "Archive Cancelled"
        }
    }
}

struct ArchiveJob: Identifiable {
    let id: UUID
    let sourceURL: URL
    let outputURL: URL
    let tempOutputURL: URL
    let logDirectory: URL
    let preset: AV1ArchivePreset
    var status: ArchiveJobStatus
    var progress: Double?
    var detail: String
    var errorMessage: String?
    var sourceSizeBytes: Int64?
    var outputSizeBytes: Int64?
    var runtimeDescription: String?
    var startedAt: Date
    var endedAt: Date?

    var isRunning: Bool {
        status == .preparing || status == .compressing || status == .verifying
    }
}
