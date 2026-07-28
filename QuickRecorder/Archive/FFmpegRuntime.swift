import Foundation
import Darwin

struct ProcessRunResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ArchiveSubprocessError: LocalizedError {
    case cancelled
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Archive operation cancelled."
        case .timedOut(let executable):
            return "Archive subprocess timed out: \(executable)"
        }
    }
}

enum FFmpegRuntimeError: LocalizedError {
    case missingRuntime
    case missingCapability(String)
    case bundledRuntimeMissing
    case checksumMismatch(String)
    case installSourceMissing
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRuntime:
            return "FFmpeg runtime missing"
        case .missingCapability(let message):
            return message
        case .bundledRuntimeMissing:
            return "Bundled FFmpeg runtime package is missing."
        case .checksumMismatch(let path):
            return "FFmpeg runtime checksum mismatch: \(path)"
        case .installSourceMissing:
            return "No local FFmpeg installation was found to install from."
        case .installFailed(let message):
            return message
        }
    }
}

struct FFmpegRuntime {
    let ffmpegURL: URL
    let ffprobeURL: URL
    let description: String
    let manifestURL: URL?

    static func resolve(cancellationRequested: @escaping () -> Bool = { false }) throws -> FFmpegRuntime {
        if cancellationRequested() { throw ArchiveSubprocessError.cancelled }
        let candidates = runtimeCandidates()
        for candidate in candidates where fd.isExecutableFile(atPath: candidate.ffmpeg.path) && fd.isExecutableFile(atPath: candidate.ffprobe.path) {
            let runtime = FFmpegRuntime(ffmpegURL: candidate.ffmpeg, ffprobeURL: candidate.ffprobe, description: candidate.description, manifestURL: candidate.manifest)
            try runtime.validateCapabilities(cancellationRequested: cancellationRequested)
            return runtime
        }
        throw FFmpegRuntimeError.missingRuntime
    }

    func validateCapabilities(cancellationRequested: @escaping () -> Bool = { false }) throws {
        let ffmpegVersion = try FFmpegRuntime.run(
            ffmpegURL,
            arguments: ["-hide_banner", "-version"],
            cancellationRequested: cancellationRequested
        )
        guard ffmpegVersion.exitCode == 0 else {
            throw FFmpegRuntimeError.missingCapability("Unable to inspect FFmpeg version.")
        }
        let ffprobeVersion = try FFmpegRuntime.run(
            ffprobeURL,
            arguments: ["-hide_banner", "-version"],
            cancellationRequested: cancellationRequested
        )
        guard ffprobeVersion.exitCode == 0 else {
            throw FFmpegRuntimeError.missingCapability("Unable to inspect FFprobe version.")
        }
        let result = try FFmpegRuntime.run(
            ffmpegURL,
            arguments: ["-hide_banner", "-encoders"],
            cancellationRequested: cancellationRequested
        )
        guard result.exitCode == 0 else {
            throw FFmpegRuntimeError.missingCapability("Unable to inspect FFmpeg encoders.")
        }
        let encoders = result.stdout + "\n" + result.stderr
        guard encoders.contains("libsvtav1") else {
            throw FFmpegRuntimeError.missingCapability("FFmpeg runtime does not include libsvtav1.")
        }
        guard encoders.contains(" aac ") || encoders.contains("aac_at") else {
            throw FFmpegRuntimeError.missingCapability("FFmpeg runtime does not include an AAC encoder.")
        }
        let svtHelp = try FFmpegRuntime.run(
            ffmpegURL,
            arguments: ["-hide_banner", "-h", "encoder=libsvtav1"],
            cancellationRequested: cancellationRequested
        )
        let svtHelpText = svtHelp.stdout + "\n" + svtHelp.stderr
        guard svtHelp.exitCode == 0 && svtHelpText.contains("-crf") else {
            throw FFmpegRuntimeError.missingCapability("FFmpeg libsvtav1 encoder does not expose CRF mode.")
        }
    }

    static func run(
        _ executableURL: URL,
        arguments: [String],
        timeout: TimeInterval = 300,
        cancellationRequested: () -> Bool = { false }
    ) throws -> ProcessRunResult {
        if cancellationRequested() { throw ArchiveSubprocessError.cancelled }
        let process = Process()
        process.launchPath = executableURL.path
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let group = DispatchGroup()
        var stdoutData = Data()
        var stderrData = Data()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        var executionError: ArchiveSubprocessError?
        while process.isRunning {
            if cancellationRequested() {
                terminate(process, forceAfter: 1)
                executionError = .cancelled
                break
            }
            if Date() >= deadline {
                terminate(process, forceAfter: 1)
                executionError = .timedOut(executableURL.lastPathComponent)
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        group.wait()
        if let executionError {
            throw executionError
        }

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return ProcessRunResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private static func terminate(_ process: Process, forceAfter delay: TimeInterval) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(delay)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }

    private static func runtimeCandidates() -> [(ffmpeg: URL, ffprobe: URL, description: String, manifest: URL?)] {
        var candidates: [(URL, URL, String, URL?)] = []

        if let resourceURL = Bundle.main.resourceURL {
            let bin = resourceURL.appendingPathComponent("FFmpegRuntime/bin", isDirectory: true)
            let manifest = resourceURL.appendingPathComponent("FFmpegRuntime/manifest.json")
            candidates.append((bin.appendingPathComponent("ffmpeg"), bin.appendingPathComponent("ffprobe"), "Bundled FFmpeg runtime", manifest))
        }

        let supportBin = ArchivePaths.runtimeBinDirectory
        candidates.append((supportBin.appendingPathComponent("ffmpeg"), supportBin.appendingPathComponent("ffprobe"), "App-managed FFmpeg runtime", ArchivePaths.runtimeManifestURL))

        if ud.bool(forKey: "archiveAllowDeveloperFFmpegRuntime") {
            for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
                candidates.append((URL(fileURLWithPath: dir).appendingPathComponent("ffmpeg"),
                                   URL(fileURLWithPath: dir).appendingPathComponent("ffprobe"),
                                   "Developer FFmpeg runtime at \(dir)",
                                   nil))
            }
        }

        return candidates
    }
}

enum FFmpegRuntimeInstaller {
    static var bundledRuntimeURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("FFmpegRuntime", isDirectory: true)
    }

    static func installBundledRuntime() throws {
        guard let source = bundledRuntimeURL, fd.fileExists(atPath: source.appendingPathComponent("manifest.json").path) else {
            throw FFmpegRuntimeError.bundledRuntimeMissing
        }
        try validateChecksums(in: source)

        let staging = ArchivePaths.runtimeDirectory.deletingLastPathComponent().appendingPathComponent("FFmpegRuntime.installing-\(UUID().uuidString)", isDirectory: true)
        try fd.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fd.copyItem(at: source, to: staging)
        try validateChecksums(in: staging)

        if fd.fileExists(atPath: ArchivePaths.runtimeDirectory.path) {
            try fd.removeItem(at: ArchivePaths.runtimeDirectory)
        }
        try fd.moveItem(at: staging, to: ArchivePaths.runtimeDirectory)

        _ = try FFmpegRuntime.resolve()
    }

    static func installFromLocalFFmpeg() throws {
        guard let ffmpeg = findLocalTool("ffmpeg"), let ffprobe = findLocalTool("ffprobe") else {
            throw FFmpegRuntimeError.installSourceMissing
        }

        try fd.createDirectory(at: ArchivePaths.runtimeBinDirectory, withIntermediateDirectories: true)
        try writeWrapper(name: "ffmpeg", target: ffmpeg)
        try writeWrapper(name: "ffprobe", target: ffprobe)

        let manifest = [
            "type": "local-wrapper",
            "ffmpeg": ffmpeg.path,
            "ffprobe": ffprobe.path,
            "installedAt": ISO8601DateFormatter().string(from: Date()),
            "note": "Development runtime wrapper. Customer builds should use a project-owned pinned runtime artifact."
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: ArchivePaths.runtimeManifestURL)
    }

    private static func validateChecksums(in runtimeDirectory: URL) throws {
        let checksumURL = runtimeDirectory.appendingPathComponent("SHA256SUMS")
        guard let content = try? String(contentsOf: checksumURL, encoding: .utf8) else {
            throw FFmpegRuntimeError.installFailed("FFmpeg runtime package is missing SHA256SUMS.")
        }

        for line in content.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let expected = String(parts[0])
            let relativePath = parts.dropFirst().joined(separator: " ")
            let fileURL = runtimeDirectory.appendingPathComponent(relativePath)
            guard fd.fileExists(atPath: fileURL.path) else {
                throw FFmpegRuntimeError.checksumMismatch(relativePath)
            }
            let actual = try sha256(fileURL)
            guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                throw FFmpegRuntimeError.checksumMismatch(relativePath)
            }
        }
    }

    private static func sha256(_ url: URL) throws -> String {
        let process = Process()
        process.launchPath = "/usr/bin/shasum"
        process.arguments = ["-a", "256", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FFmpegRuntimeError.installFailed("Unable to calculate runtime checksum.")
        }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.split(separator: " ").first.map(String.init) ?? ""
    }

    private static func findLocalTool(_ name: String) -> URL? {
        for path in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"] where fd.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let result = try? FFmpegRuntime.run(URL(fileURLWithPath: "/usr/bin/which"), arguments: [name])
        if let path = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty, fd.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func writeWrapper(name: String, target: URL) throws {
        let wrapper = ArchivePaths.runtimeBinDirectory.appendingPathComponent(name)
        let script = "#!/bin/sh\nexec \"\(target.path)\" \"$@\"\n"
        try script.write(to: wrapper, atomically: true, encoding: .utf8)
        try fd.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
    }
}
