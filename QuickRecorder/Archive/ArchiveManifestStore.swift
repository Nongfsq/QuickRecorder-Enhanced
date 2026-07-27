import Foundation
import ArchiveJobCore

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

struct ArchiveManifestLoadIssue: Identifiable {
    let id = UUID()
    let manifestURL: URL
    let message: String
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

    static func writeManifest(job: ArchiveJob) throws {
        guard ArchivePathSafety.isTaskOwned(job.logDirectory.appendingPathComponent("manifest.json"), jobsRoot: ArchivePaths.jobsDirectory, jobID: job.id) else {
            throw NSError(domain: "QuickRecorderArchive", code: 40, userInfo: [NSLocalizedDescriptionKey: "Archive manifest path is outside its task directory."])
        }
        let validation = job.validation?.reduce(into: [String: JSONValue]()) { result, entry in
            if let value = JSONValue(foundationValue: entry.value) {
                result[entry.key] = value
            }
        }
        let manifest = ArchiveJobManifest(
            id: job.id,
            source: job.sourceURL.path,
            output: job.outputURL.path,
            tempOutput: job.tempOutputURL.path,
            status: job.status,
            detail: job.detail,
            crf: job.preset.crf,
            svtPreset: job.preset.svtPreset,
            gop: job.preset.gop,
            audioMode: job.preset.audioMode.rawValue,
            progress: job.progress,
            error: job.errorMessage,
            runtime: job.runtimeDescription,
            sourceSizeBytes: job.sourceSizeBytes,
            outputSizeBytes: job.outputSizeBytes,
            command: job.command,
            validation: validation,
            startedAt: job.startedAt,
            updatedAt: job.updatedAt,
            endedAt: job.endedAt
        )
        let data = try ArchiveManifestCodec.encode(manifest)
        try fd.createDirectory(at: job.logDirectory, withIntermediateDirectories: true)
        try data.write(to: job.logDirectory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    static func loadJobs() -> (jobs: [ArchiveJob], issues: [ArchiveManifestLoadIssue]) {
        guard let directories = try? fd.contentsOfDirectory(
            at: ArchivePaths.jobsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], [])
        }

        var jobs: [ArchiveJob] = []
        var issues: [ArchiveManifestLoadIssue] = []
        for directory in directories {
            guard UUID(uuidString: directory.lastPathComponent) != nil else { continue }
            let manifestURL = directory.appendingPathComponent("manifest.json")
            guard fd.fileExists(atPath: manifestURL.path) else { continue }
            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try ArchiveManifestCodec.decode(data)
                guard directory.lastPathComponent.caseInsensitiveCompare(manifest.id.uuidString) == .orderedSame else {
                    throw NSError(domain: "QuickRecorderArchive", code: 44, userInfo: [NSLocalizedDescriptionKey: "Archive manifest UUID does not match its task directory."])
                }
                jobs.append(makeJob(from: manifest, directory: directory))
            } catch {
                issues.append(ArchiveManifestLoadIssue(manifestURL: manifestURL, message: error.localizedDescription))
            }
        }
        return (jobs, issues)
    }

    private static func makeJob(from manifest: ArchiveJobManifest, directory: URL) -> ArchiveJob {
        let audioMode = AV1ArchiveAudioMode(rawValue: manifest.audioMode) ?? .aacMono64k
        let validation = manifest.validation?.mapValues(\.foundationValue)
        return ArchiveJob(
            id: manifest.id,
            sourceURL: URL(fileURLWithPath: manifest.source),
            outputURL: URL(fileURLWithPath: manifest.output),
            tempOutputURL: tempOutputURL(in: directory),
            logDirectory: directory,
            preset: AV1ArchivePreset(crf: manifest.crf, svtPreset: manifest.svtPreset, gop: manifest.gop, audioMode: audioMode),
            status: manifest.status,
            progress: manifest.progress,
            detail: manifest.detail,
            errorMessage: manifest.error,
            sourceSizeBytes: manifest.sourceSizeBytes,
            outputSizeBytes: manifest.outputSizeBytes,
            runtimeDescription: manifest.runtime,
            command: manifest.command,
            validation: validation,
            startedAt: manifest.startedAt,
            updatedAt: manifest.updatedAt,
            endedAt: manifest.endedAt
        )
    }
}
