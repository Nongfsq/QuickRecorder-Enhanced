import Foundation

enum ArchivePaths {
    static var applicationSupportDirectory: URL {
        let base = fd.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("QuickRecorder", isDirectory: true)
    }

    static var jobsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("ArchiveJobs", isDirectory: true)
    }

    static var runtimeDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("FFmpegRuntime", isDirectory: true)
    }

    static var runtimeBinDirectory: URL {
        runtimeDirectory.appendingPathComponent("bin", isDirectory: true)
    }

    static var runtimeManifestURL: URL {
        runtimeDirectory.appendingPathComponent("manifest.json")
    }
}

enum ArchiveManifestStore {
    static func createJobDirectory(id: UUID) throws -> URL {
        let directory = ArchivePaths.jobsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try fd.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func tempOutputURL(in directory: URL) -> URL {
        directory.appendingPathComponent("encoded-av1.mp4")
    }

    static func write(_ string: String, to url: URL) {
        try? string.write(to: url, atomically: true, encoding: .utf8)
    }

    static func writeManifest(job: ArchiveJob, command: [String]? = nil, validation: [String: Any]? = nil) {
        var manifest: [String: Any] = [
            "id": job.id.uuidString,
            "source": job.sourceURL.path,
            "output": job.outputURL.path,
            "tempOutput": job.tempOutputURL.path,
            "status": job.status.rawValue,
            "detail": job.detail,
            "crf": job.preset.crf,
            "svtPreset": job.preset.svtPreset,
            "gop": job.preset.gop,
            "audioMode": job.preset.audioMode.rawValue,
            "startedAt": ISO8601DateFormatter().string(from: job.startedAt)
        ]
        if let endedAt = job.endedAt {
            manifest["endedAt"] = ISO8601DateFormatter().string(from: endedAt)
        }
        if let runtimeDescription = job.runtimeDescription {
            manifest["runtime"] = runtimeDescription
        }
        if let errorMessage = job.errorMessage {
            manifest["error"] = errorMessage
        }
        if let sourceSizeBytes = job.sourceSizeBytes {
            manifest["sourceSizeBytes"] = sourceSizeBytes
        }
        if let outputSizeBytes = job.outputSizeBytes {
            manifest["outputSizeBytes"] = outputSizeBytes
        }
        if let command = command {
            manifest["command"] = command
        }
        if let validation = validation {
            manifest["validation"] = validation
        }
        if let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: job.logDirectory.appendingPathComponent("manifest.json"))
        }
    }
}
