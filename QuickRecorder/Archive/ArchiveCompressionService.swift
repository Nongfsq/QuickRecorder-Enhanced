import Foundation
import SwiftUI

final class ArchiveCompressionService: ObservableObject {
    static let shared = ArchiveCompressionService()

    @Published private(set) var jobsBySource: [String: ArchiveJob] = [:]

    private var processes: [UUID: Process] = [:]
    private var quitAfterSourcePaths = Set<String>()
    private let queue = DispatchQueue(label: "quickrecorder.archive.service", qos: .utility)
    private let processLock = DispatchQueue(label: "quickrecorder.archive.process-lock")

    private init() {}

    func recordingDidComplete(url: URL) {
        guard ud.bool(forKey: "autoCreateAV1ArchiveAfterRecording") else { return }
        guard AV1ArchiveCommandBuilder.isSupportedSource(url) else { return }
        startArchive(for: url)
    }

    func job(for sourceURL: URL) -> ArchiveJob? {
        jobsBySource[sourceURL.path]
    }

    func startArchive(for sourceURL: URL) {
        guard AV1ArchiveCommandBuilder.isSupportedSource(sourceURL) else {
            setImmediateFailure(sourceURL: sourceURL, message: "Unsupported source for AV1 archive.")
            return
        }
        if let existing = job(for: sourceURL), existing.isRunning {
            return
        }

        let preset = AV1ArchivePreset.current
        let id = UUID()
        do {
            let logDirectory = try ArchiveManifestStore.createJobDirectory(id: id)
            let outputURL = AV1ArchiveCommandBuilder.defaultOutputURL(for: sourceURL, preset: preset)
            let tempOutputURL = ArchiveManifestStore.tempOutputURL(in: logDirectory)
            let sourceSize = fileSize(sourceURL)
            let job = ArchiveJob(
                id: id,
                sourceURL: sourceURL,
                outputURL: outputURL,
                tempOutputURL: tempOutputURL,
                logDirectory: logDirectory,
                preset: preset,
                status: .preparing,
                progress: nil,
                detail: "Preparing AV1 archive",
                errorMessage: nil,
                sourceSizeBytes: sourceSize,
                outputSizeBytes: nil,
                runtimeDescription: nil,
                startedAt: Date(),
                endedAt: nil
            )
            update(job)
            queue.async { self.run(job: job) }
        } catch {
            setImmediateFailure(sourceURL: sourceURL, message: error.localizedDescription)
        }
    }

    func cancel(jobID: UUID) {
        processLock.async {
            if let process = self.processes[jobID], process.isRunning {
                process.terminate()
            }
        }
    }

    func cancelAll() {
        processLock.async {
            for (_, process) in self.processes where process.isRunning {
                process.terminate()
            }
        }
    }

    func installRuntime() {
        queue.async {
            do {
                do {
                    try FFmpegRuntimeInstaller.installBundledRuntime()
                } catch FFmpegRuntimeError.bundledRuntimeMissing where ud.bool(forKey: "archiveAllowDeveloperFFmpegRuntime") {
                    try FFmpegRuntimeInstaller.installFromLocalFFmpeg()
                }
                DispatchQueue.main.async {
                    for (_, job) in self.jobsBySource where job.status == .runtimeMissing {
                        var updated = job
                        updated.status = .preparing
                        updated.detail = "FFmpeg runtime installed. Start the archive again."
                        updated.errorMessage = nil
                        self.jobsBySource[job.sourceURL.path] = updated
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = createAlert(title: "Install FFmpeg Runtime", message: error.localizedDescription, button1: "OK")
                    _ = alert.runModal()
                }
            }
        }
    }

    func installRuntimeFromLocalFFmpeg() {
        queue.async {
            do {
                try FFmpegRuntimeInstaller.installFromLocalFFmpeg()
            } catch {
                DispatchQueue.main.async {
                    let alert = createAlert(title: "Install FFmpeg Runtime", message: error.localizedDescription, button1: "OK")
                    _ = alert.runModal()
                }
            }
        }
    }

    func quitWhenJobFinishes(for sourceURL: URL) {
        DispatchQueue.main.async {
            self.quitAfterSourcePaths.insert(sourceURL.path)
            if let job = self.jobsBySource[sourceURL.path], !job.isRunning {
                NSApp.terminate(nil)
            }
        }
    }

    private func run(job initialJob: ArchiveJob) {
        var job = initialJob
        var command: [String] = []
        var stderrLog = ""
        var stdoutLog = ""

        do {
            let runtime = try FFmpegRuntime.resolve()
            job.runtimeDescription = runtime.description
            job.detail = runtime.description
            command = [runtime.ffmpegURL.path] + AV1ArchiveCommandBuilder.command(runtime: runtime, sourceURL: job.sourceURL, tempOutputURL: job.tempOutputURL, preset: job.preset)
            ArchiveManifestStore.writeManifest(job: job, command: command)

            updateStatus(jobID: job.id, sourceURL: job.sourceURL, status: .compressing, progress: 0, detail: "Compressing")
            let result = try runFFmpeg(runtime: runtime, arguments: Array(command.dropFirst()), job: job) { progress, detail, stdout, stderr in
                stdoutLog += stdout
                stderrLog += stderr
                self.updateStatus(jobID: job.id, sourceURL: job.sourceURL, status: .compressing, progress: progress, detail: detail)
            }
            ArchiveManifestStore.write(stdoutLog, to: job.logDirectory.appendingPathComponent("ffmpeg-stdout.log"))
            ArchiveManifestStore.write(stderrLog, to: job.logDirectory.appendingPathComponent("ffmpeg-stderr.log"))

            if result.exitCode != 0 {
                if result.exitCode == 15 {
                    finish(job: job, status: .cancelled, detail: "Archive cancelled", error: nil, command: command)
                    try? fd.removeItem(at: job.tempOutputURL)
                    return
                }
                throw NSError(domain: "QuickRecorderArchive", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: "FFmpeg failed. See archive logs for details."])
            }

            updateStatus(jobID: job.id, sourceURL: job.sourceURL, status: .verifying, progress: 1, detail: "Verifying")
            let validation = try ArchiveTimestampValidator.validate(runtime: runtime, sourceURL: job.sourceURL, outputURL: job.tempOutputURL, preset: job.preset, ffmpegLog: stderrLog, logDirectory: job.logDirectory)

            if fd.fileExists(atPath: job.outputURL.path) {
                throw NSError(domain: "QuickRecorderArchive", code: 20, userInfo: [NSLocalizedDescriptionKey: "Output already exists."])
            }
            try fd.moveItem(at: job.tempOutputURL, to: job.outputURL)
            job.outputSizeBytes = fileSize(job.outputURL)
            job.status = .completed
            job.detail = "Wrote \(job.outputURL.lastPathComponent)"
            job.endedAt = Date()
            ArchiveManifestStore.writeManifest(job: job, command: command, validation: validation)
            update(job)
            SCContext.showNotification(title: "Archive Complete".local, body: String(format: "File saved to: %@".local, job.outputURL.path), id: "quickrecorder.archive.\(UUID().uuidString)")
        } catch FFmpegRuntimeError.missingRuntime {
            finish(job: job, status: .runtimeMissing, detail: "FFmpeg runtime missing", error: "Install FFmpeg Runtime", command: command)
        } catch {
            try? fd.removeItem(at: job.tempOutputURL)
            finish(job: job, status: .failed, detail: "Archive Failed", error: error.localizedDescription, command: command)
        }
    }

    private func runFFmpeg(runtime: FFmpegRuntime, arguments: [String], job: ArchiveJob, progressHandler: @escaping (Double?, String, String, String) -> Void) throws -> ProcessRunResult {
        let process = Process()
        process.launchPath = runtime.ffmpegURL.path
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var stdout = ""
        var stderr = ""
        var duration: TimeInterval?

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            stdout += chunk
            progressHandler(nil, "Compressing", chunk, "")
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            stderr += chunk
            if duration == nil { duration = ArchiveProgressParser.duration(from: chunk) ?? ArchiveProgressParser.duration(from: stderr) }
            var progress: Double?
            if let duration = duration, duration > 0, let encoded = ArchiveProgressParser.encodedTime(from: chunk) {
                progress = min(max(encoded / duration, 0), 0.999)
            }
            let detail = progress.map { "Compressing \(Int($0 * 100))%" } ?? "Compressing"
            progressHandler(progress, detail, "", chunk)
        }

        try process.run()
        processLock.sync {
            processes[job.id] = process
        }
        process.waitUntilExit()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        processLock.sync {
            processes[job.id] = nil
        }

        return ProcessRunResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private func updateStatus(jobID: UUID, sourceURL: URL, status: ArchiveJobStatus, progress: Double?, detail: String) {
        DispatchQueue.main.async {
            guard var job = self.jobsBySource[sourceURL.path], job.id == jobID else { return }
            job.status = status
            job.progress = progress
            job.detail = detail
            self.jobsBySource[sourceURL.path] = job
        }
    }

    private func finish(job: ArchiveJob, status: ArchiveJobStatus, detail: String, error: String?, command: [String]?) {
        var finished = job
        finished.status = status
        finished.detail = detail
        finished.errorMessage = error
        finished.endedAt = Date()
        ArchiveManifestStore.writeManifest(job: finished, command: command)
        update(finished)
        if status == .failed {
            SCContext.showNotification(title: "Archive Failed".local, body: error ?? detail, id: "quickrecorder.archive.error.\(UUID().uuidString)")
        }
    }

    private func update(_ job: ArchiveJob) {
        DispatchQueue.main.async {
            self.jobsBySource[job.sourceURL.path] = job
            if self.quitAfterSourcePaths.contains(job.sourceURL.path), !job.isRunning {
                NSApp.terminate(nil)
            }
        }
    }

    private func setImmediateFailure(sourceURL: URL, message: String) {
        do {
            let id = UUID()
            let preset = AV1ArchivePreset.current
            let logDirectory = try ArchiveManifestStore.createJobDirectory(id: id)
            let job = ArchiveJob(
                id: id,
                sourceURL: sourceURL,
                outputURL: AV1ArchiveCommandBuilder.defaultOutputURL(for: sourceURL, preset: preset),
                tempOutputURL: ArchiveManifestStore.tempOutputURL(in: logDirectory),
                logDirectory: logDirectory,
                preset: preset,
                status: .failed,
                progress: nil,
                detail: "Archive Failed",
                errorMessage: message,
                sourceSizeBytes: fileSize(sourceURL),
                outputSizeBytes: nil,
                runtimeDescription: nil,
                startedAt: Date(),
                endedAt: Date()
            )
            ArchiveManifestStore.writeManifest(job: job)
            update(job)
        } catch {
            print(message)
        }
    }

    private func fileSize(_ url: URL) -> Int64 {
        let attrs = try? fd.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? Int64 ?? 0
    }
}
