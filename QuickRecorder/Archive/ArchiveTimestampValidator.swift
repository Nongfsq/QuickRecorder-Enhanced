import Foundation

enum ArchiveValidationError: LocalizedError {
    case failed([String])

    var errorDescription: String? {
        switch self {
        case .failed(let issues):
            return issues.joined(separator: "\n")
        }
    }
}

enum ArchiveTimestampValidator {
    static func validate(runtime: FFmpegRuntime, sourceURL: URL, outputURL: URL, preset: AV1ArchivePreset, ffmpegLog: String, logDirectory: URL) throws -> [String: Any] {
        var issues: [String] = []

        for warning in ["Non-monotonic DTS", "Packets poorly interleaved", "failed to avoid negative timestamp", "missing picture in access unit"] {
            if ffmpegLog.localizedCaseInsensitiveContains(warning) {
                issues.append("ffmpeg log contains \(warning)")
            }
        }

        if !fd.fileExists(atPath: outputURL.path) {
            issues.append("output file missing")
        } else if fileSize(outputURL) <= 0 {
            issues.append("output file is empty")
        }

        let ffprobeWarning = (try? FFmpegRuntime.run(runtime.ffprobeURL, arguments: ["-v", "warning", outputURL.path])) ?? ProcessRunResult(exitCode: 1, stdout: "", stderr: "ffprobe failed")
        let ffprobeWarningText = ffprobeWarning.stdout + ffprobeWarning.stderr
        ArchiveManifestStore.write(ffprobeWarningText, to: logDirectory.appendingPathComponent("ffprobe-warning.log"))
        if ffprobeWarning.exitCode != 0 || !ffprobeWarningText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("ffprobe warning check failed")
        }

        let sourceProbe = probe(runtime: runtime, url: sourceURL)
        let outputProbe = probe(runtime: runtime, url: outputURL)
        let sourceVideo = firstStream(sourceProbe, type: "video")
        let outputVideo = firstStream(outputProbe, type: "video")
        let sourceAudio = firstStream(sourceProbe, type: "audio")
        let outputAudio = firstStream(outputProbe, type: "audio")

        if string(outputVideo?["codec_name"]) != "av1" {
            issues.append("output video codec is not AV1")
        }
        if int(sourceVideo?["width"]) != int(outputVideo?["width"]) || int(sourceVideo?["height"]) != int(outputVideo?["height"]) {
            issues.append("output resolution does not match source")
        }
        if !audioPolicyPass(mode: preset.audioMode, sourceAudio: sourceAudio, outputAudio: outputAudio) {
            issues.append("audio policy failed")
        }

        let durationDelta = abs(duration(outputProbe, stream: outputVideo) - duration(sourceProbe, stream: sourceVideo))
        let durationTolerance = max(1.0, duration(sourceProbe, stream: sourceVideo) * 0.001)
        if durationDelta > durationTolerance {
            issues.append("duration delta exceeds tolerance")
        }

        let sourceFrameCount = frameCount(sourceVideo)
        let outputFrameCount = frameCount(outputVideo)
        if sourceFrameCount > 0 && outputFrameCount > 0 {
            let delta = abs(Double(outputFrameCount - sourceFrameCount)) / Double(sourceFrameCount)
            if delta > 0.001 {
                issues.append("frame count delta exceeds tolerance")
            }
        }

        let videoPacketStats = packetStats(runtime: runtime, url: outputURL, stream: "v:0")
        if !videoPacketStats.issues.isEmpty {
            issues.append(contentsOf: videoPacketStats.issues.map { "video packet \($0)" })
        }
        let audioPacketStats = outputAudio == nil ? PacketStats(count: 0, issues: []) : packetStats(runtime: runtime, url: outputURL, stream: "a:0")
        if !audioPacketStats.issues.isEmpty {
            issues.append(contentsOf: audioPacketStats.issues.map { "audio packet \($0)" })
        }

        let validation: [String: Any] = [
            "status": issues.isEmpty ? "pass" : "fail",
            "issues": issues,
            "durationDeltaSeconds": durationDelta,
            "sourceFrameCount": sourceFrameCount,
            "outputFrameCount": outputFrameCount,
            "videoPacketCount": videoPacketStats.count,
            "audioPacketCount": audioPacketStats.count,
            "outputCodec": string(outputVideo?["codec_name"]) ?? "",
            "outputWidth": int(outputVideo?["width"]),
            "outputHeight": int(outputVideo?["height"])
        ]

        if let data = try? JSONSerialization.data(withJSONObject: validation, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: logDirectory.appendingPathComponent("validation.json"))
        }

        if !issues.isEmpty {
            throw ArchiveValidationError.failed(issues)
        }
        return validation
    }

    private static func probe(runtime: FFmpegRuntime, url: URL) -> [String: Any] {
        guard let result = try? FFmpegRuntime.run(runtime.ffprobeURL, arguments: ["-v", "error", "-show_streams", "-show_format", "-of", "json", url.path]),
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private static func firstStream(_ probe: [String: Any], type: String) -> [String: Any]? {
        guard let streams = probe["streams"] as? [[String: Any]] else { return nil }
        return streams.first { string($0["codec_type"]) == type }
    }

    private static func duration(_ probe: [String: Any], stream: [String: Any]?) -> Double {
        if let value = double(stream?["duration"]) { return value }
        if let format = probe["format"] as? [String: Any], let value = double(format["duration"]) { return value }
        return 0
    }

    private static func frameCount(_ stream: [String: Any]?) -> Int {
        max(0, int(stream?["nb_frames"]))
    }

    private static func audioPolicyPass(mode: AV1ArchiveAudioMode, sourceAudio: [String: Any]?, outputAudio: [String: Any]?) -> Bool {
        guard sourceAudio != nil else { return outputAudio == nil }
        guard let outputAudio = outputAudio else { return false }
        switch mode {
        case .copy:
            return string(sourceAudio?["codec_name"]) == string(outputAudio["codec_name"])
        case .aacMono48k, .aacMono64k:
            return string(outputAudio["codec_name"]) == "aac"
                && int(outputAudio["channels"]) == 1
                && string(outputAudio["sample_rate"]) == "48000"
        }
    }

    private struct PacketStats {
        let count: Int
        let issues: [String]
    }

    private static func packetStats(runtime: FFmpegRuntime, url: URL, stream: String) -> PacketStats {
        guard let result = try? FFmpegRuntime.run(runtime.ffprobeURL, arguments: [
            "-v", "error",
            "-select_streams", stream,
            "-show_packets",
            "-show_entries", "packet=pts_time,dts_time",
            "-of", "csv=p=0",
            url.path
        ]), result.exitCode == 0 else {
            return PacketStats(count: 0, issues: ["timestamp probe failed"])
        }

        var previousDTS: Double?
        var seenDTS = Set<String>()
        var issues: [String] = []
        var count = 0

        for rawLine in result.stdout.split(whereSeparator: \.isNewline) {
            let parts = rawLine.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let ptsText = String(parts[0])
            let dtsText = String(parts[1])
            guard let pts = Double(ptsText), let dts = Double(dtsText) else {
                issues.append("missing pts/dts")
                continue
            }
            count += 1
            if pts < 0 || dts < 0 { issues.append("negative timestamp") }
            if let previousDTS = previousDTS, dts < previousDTS {
                issues.append("DTS went backwards")
            }
            if seenDTS.contains(dtsText) {
                issues.append("duplicate DTS")
            }
            seenDTS.insert(dtsText)
            previousDTS = dts
            if issues.count > 10 { break }
        }

        return PacketStats(count: count, issues: Array(Set(issues)).sorted())
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let attrs = try? fd.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? Int64 ?? 0
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func int(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let string = value as? String { return Int(string) ?? 0 }
        if let number = value as? NSNumber { return number.intValue }
        return 0
    }

    private static func double(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let string = value as? String { return Double(string) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }
}
