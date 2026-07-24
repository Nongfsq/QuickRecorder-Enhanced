import Foundation

enum AV1ArchiveCommandBuilder {
    static func command(runtime: FFmpegRuntime, sourceURL: URL, tempOutputURL: URL, preset: AV1ArchivePreset) -> [String] {
        [
            "-hide_banner",
            "-nostdin",
            "-y",
            "-fflags",
            "+genpts",
            "-i",
            sourceURL.path,
            "-map",
            "0:v:0",
            "-map",
            "0:a:0?",
            "-c:v",
            "libsvtav1",
            "-preset",
            "\(preset.svtPreset)",
            "-crf",
            "\(preset.crf)",
            "-g",
            "\(preset.gop)",
            "-pix_fmt",
            "yuv420p",
            "-fps_mode",
            "vfr",
            "-enc_time_base:v",
            "demux",
            "-video_track_timescale",
            "60000",
            "-avoid_negative_ts",
            "make_zero"
        ] + preset.audioMode.ffmpegArguments + [
            "-max_interleave_delta",
            "0",
            "-movflags",
            "+faststart",
            tempOutputURL.path
        ]
    }

    static func defaultOutputURL(for sourceURL: URL, preset: AV1ArchivePreset) -> URL {
        let base = sourceURL.deletingPathExtension().path + preset.outputSuffix
        return uniqueURL(URL(fileURLWithPath: base))
    }

    static func isSupportedSource(_ url: URL) -> Bool {
        ["mp4", "mov"].contains(url.pathExtension.lowercased())
    }

    private static func uniqueURL(_ url: URL) -> URL {
        guard fd.fileExists(atPath: url.path) else { return url }
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for index in 2...999 {
            let candidate = directory.appendingPathComponent("\(base)-\(index)").appendingPathExtension(ext)
            if !fd.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent("\(base)-\(UUID().uuidString)").appendingPathExtension(ext)
    }
}
