import Foundation
import SwiftUI
import ArchiveJobCore
import Darwin

final class ArchiveCompressionService: ObservableObject {
    static let shared = ArchiveCompressionService()

    @Published private(set) var jobsByID: [UUID: ArchiveJob] = [:]
    @Published private(set) var manifestLoadIssues: [ArchiveManifestLoadIssue] = []
    @Published private(set) var recoveryCleanupError: String?

    private var activeJobIDBySource: [String: UUID] = [:]
    private var processes: [UUID: Process] = [:]
    private var cancelRequestedIDs = Set<UUID>()
    private var quitAfterSourcePaths = Set<String>()
    private var completionWaiters: [() -> Void] = []
    private var acceptsNewJobs = true
    private var lastPersistedProgress: [UUID: Double] = [:]
    private var closedProgressPersistenceIDs = Set<UUID>()
    private let queue = DispatchQueue(label: "quickrecorder.archive.service", qos: .utility)
    private let persistenceQueue = DispatchQueue(label: "quickrecorder.archive.persistence", qos: .utility)
    private let processLock = DispatchQueue(label: "quickrecorder.archive.process-lock")

    private init() {
        restorePersistedJobs()
    }

    var runningJobCount: Int {
        jobsByID.values.filter(\.isRunning).count
    }

    var hasRunningJobs: Bool {
        runningJobCount > 0
    }

    var recoveryJobs: [ArchiveJob] {
        jobsByID.values.filter {
            let disposition = recoveryDisposition(for: $0)
            return disposition != .alreadyCompleted && disposition != .noAction
        }.sorted { $0.startedAt < $1.startedAt }
    }

    var interruptedJobs: [ArchiveJob] {
        recoveryJobs
    }

    func recoveryDisposition(for job: ArchiveJob) -> ArchiveRecoveryDisposition {
        ArchiveRecoveryClassifier.classify(
            status: job.status,
            sourceExists: fd.fileExists(atPath: job.sourceURL.path),
            outputExists: fd.fileExists(atPath: job.outputURL.path),
            temporaryOutputExists: fd.fileExists(atPath: job.tempOutputURL.path)
        )
    }

    func recordingDidComplete(url: URL) {
        guard ud.bool(forKey: "autoCreateAV1ArchiveAfterRecording") else { return }
        guard AV1ArchiveCommandBuilder.isSupportedSource(url) else { return }
        startArchive(for: url)
    }

    func job(for sourceURL: URL) -> ArchiveJob? {
        if let activeID = activeJobIDBySource[sourceURL.path], let active = jobsByID[activeID] {
            return active
        }
        return jobsByID.values
            .filter { $0.sourceURL.path == sourceURL.path }
            .max { $0.startedAt < $1.startedAt }
    }

    func job(id: UUID) -> ArchiveJob? {
        jobsByID[id]
    }

    func startArchive(for sourceURL: URL) {
        startArchive(for: sourceURL, preset: .current, reusing: nil)
    }

    func restart(jobID: UUID) {
        guard var job = jobsByID[jobID] else { return }
        let disposition = recoveryDisposition(for: job)
        guard disposition == .restartEncoding || disposition == .completedOutputMissing else { return }
        guard fd.fileExists(atPath: job.sourceURL.path) else {
            job.errorMessage = "The source recording is missing."
            job.detail = "Archive recovery needs attention"
            job.updatedAt = Date()
            persistOrPublishFailure(job)
            return
        }
        guard !fd.fileExists(atPath: job.outputURL.path) else {
            job.errorMessage = "Output already exists."
            job.detail = "Archive recovery needs attention"
            job.updatedAt = Date()
            persistOrPublishFailure(job)
            return
        }
        do {
            try ensureTemporaryOutputIsInactive(job)
            try removeTemporaryOutputIfOwned(job)
        } catch {
            job.errorMessage = error.localizedDescription
            job.detail = "Archive recovery needs attention"
            job.updatedAt = Date()
            persistOrPublishFailure(job)
            return
        }
        startArchive(for: job.sourceURL, preset: job.preset, reusing: job)
    }

    func recoverTemporaryOutput(jobID: UUID) {
        guard let job = jobsByID[jobID], recoveryDisposition(for: job) == .validateTemporaryOutput else { return }
        beginRecoveryValidation(job: job, candidateURL: job.tempOutputURL, moveToFinalOutput: true)
    }

    func recoverFinalOutput(jobID: UUID) {
        guard let job = jobsByID[jobID], recoveryDisposition(for: job) == .validateFinalOutput else { return }
        beginRecoveryValidation(job: job, candidateURL: job.outputURL, moveToFinalOutput: false)
    }

    private func beginRecoveryValidation(job initialJob: ArchiveJob, candidateURL: URL, moveToFinalOutput: Bool) {
        var job = initialJob
        job.status = .verifying
        job.progress = 1
        job.detail = "Verifying recovered archive"
        job.errorMessage = nil
        job.updatedAt = Date()
        do {
            try ArchiveManifestStore.writeManifest(job: job)
            jobsByID[job.id] = job
            activeJobIDBySource[job.sourceURL.path] = job.id
        } catch {
            job.status = .failed
            job.detail = "Archive manifest write failed"
            job.errorMessage = error.localizedDescription
            job.endedAt = Date()
            jobsByID[job.id] = job
            return
        }
        queue.async {
            self.validateAndPublishRecoveredOutput(job, candidateURL: candidateURL, moveToFinalOutput: moveToFinalOutput)
        }
    }

    func removeRecoveryJob(jobID: UUID) {
        guard var job = jobsByID[jobID], !job.isRunning else { return }
        do {
            try ensureTemporaryOutputIsInactive(job)
            try removeTaskDirectory(job.logDirectory, jobID: job.id)
            jobsByID[jobID] = nil
            if activeJobIDBySource[job.sourceURL.path] == jobID {
                activeJobIDBySource[job.sourceURL.path] = nil
            }
            recoveryCleanupError = nil
        } catch {
            job.errorMessage = error.localizedDescription
            job.detail = "Unable to remove recovery record"
            job.updatedAt = Date()
            jobsByID[jobID] = job
            recoveryCleanupError = error.localizedDescription
        }
    }

    func removeManifestLoadIssue(issueID: UUID) {
        guard let issue = manifestLoadIssues.first(where: { $0.id == issueID }) else { return }
        do {
            let directory = issue.manifestURL.deletingLastPathComponent()
            guard let jobID = UUID(uuidString: directory.lastPathComponent) else {
                throw NSError(domain: "QuickRecorderArchive", code: 46, userInfo: [NSLocalizedDescriptionKey: "Recovery record directory is invalid."])
            }
            try removeTaskDirectory(directory, jobID: jobID)
            manifestLoadIssues.removeAll { $0.id == issueID }
            recoveryCleanupError = nil
        } catch {
            recoveryCleanupError = error.localizedDescription
        }
    }

    func clearAllRecoveryRecords() {
        let jobIDs = recoveryJobs.map(\.id)
        let issueIDs = manifestLoadIssues.map(\.id)
        for jobID in jobIDs {
            removeRecoveryJob(jobID: jobID)
        }
        for issueID in issueIDs {
            removeManifestLoadIssue(issueID: issueID)
        }
    }

    private func startArchive(for sourceURL: URL, preset: AV1ArchivePreset, reusing existingJob: ArchiveJob?) {
        guard acceptsNewJobs else { return }
        guard AV1ArchiveCommandBuilder.isSupportedSource(sourceURL) else {
            setImmediateFailure(sourceURL: sourceURL, message: "Unsupported source for AV1 archive.")
            return
        }
        if let activeID = activeJobIDBySource[sourceURL.path], jobsByID[activeID]?.isRunning == true {
            return
        }

        let id = existingJob?.id ?? UUID()
        do {
            let logDirectory: URL
            if let existingDirectory = existingJob?.logDirectory {
                logDirectory = existingDirectory
            } else {
                logDirectory = try ArchiveManifestStore.createJobDirectory(id: id)
            }
            let outputURL = existingJob?.outputURL ?? AV1ArchiveCommandBuilder.defaultOutputURL(for: sourceURL, preset: preset)
            let now = Date()
            let job = ArchiveJob(
                id: id,
                sourceURL: sourceURL,
                outputURL: outputURL,
                tempOutputURL: ArchiveManifestStore.tempOutputURL(in: logDirectory),
                logDirectory: logDirectory,
                preset: preset,
                status: .preparing,
                progress: nil,
                detail: "Preparing AV1 archive",
                errorMessage: nil,
                sourceSizeBytes: fileSize(sourceURL),
                outputSizeBytes: nil,
                runtimeDescription: nil,
                command: nil,
                validation: nil,
                startedAt: existingJob?.startedAt ?? now,
                updatedAt: now,
                endedAt: nil
            )
            jobsByID[id] = job
            activeJobIDBySource[sourceURL.path] = id
            try persistAndPublish(job)
            queue.async { self.run(job: job) }
        } catch {
            if activeJobIDBySource[sourceURL.path] == id {
                activeJobIDBySource[sourceURL.path] = nil
            }
            jobsByID[id] = nil
            setImmediateFailure(sourceURL: sourceURL, message: error.localizedDescription)
        }
    }

    func cancel(jobID: UUID) {
        guard var job = jobsByID[jobID], job.isRunning, job.status != .cancelling else { return }
        job.status = .cancelling
        job.detail = "Cancelling archive"
        job.updatedAt = Date()
        _ = processLock.sync { cancelRequestedIDs.insert(jobID) }
        persistOrPublishFailure(job)
        processLock.async {
            if let process = self.processes[jobID], process.isRunning {
                process.terminate()
                self.processLock.asyncAfter(deadline: .now() + 3) {
                    guard self.processes[jobID] === process, process.isRunning else { return }
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }

    func cancelAllAndWait(completion: @escaping () -> Void) {
        acceptsNewJobs = false
        completionWaiters.append(completion)
        let runningIDs = jobsByID.values.filter(\.isRunning).map(\.id)
        if runningIDs.isEmpty {
            drainCompletionWaitersIfIdle()
            return
        }
        runningIDs.forEach(cancel(jobID:))
    }

    func waitForAllJobsToFinish(completion: @escaping () -> Void) {
        acceptsNewJobs = false
        completionWaiters.append(completion)
        drainCompletionWaitersIfIdle()
    }

    func resumeAcceptingJobs() {
        acceptsNewJobs = true
        completionWaiters.removeAll()
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
                    for job in self.jobsByID.values where job.status == .runtimeMissing {
                        var updated = job
                        updated.detail = "FFmpeg runtime installed. Start the archive again."
                        updated.errorMessage = nil
                        updated.updatedAt = Date()
                        self.persistOrPublishFailure(updated)
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
        quitAfterSourcePaths.insert(sourceURL.path)
        if let job = job(for: sourceURL), !job.isRunning {
            NSApp.terminate(nil)
        }
    }

    private func run(job initialJob: ArchiveJob) {
        var job = initialJob
        var stderrLog = ""
        var stdoutLog = ""

        do {
            if isCancellationRequested(job.id) {
                try finishCancelled(&job)
                return
            }
            let runtime = try FFmpegRuntime.resolve()
            job.runtimeDescription = runtime.description
            job.command = [runtime.ffmpegURL.path] + AV1ArchiveCommandBuilder.command(runtime: runtime, sourceURL: job.sourceURL, tempOutputURL: job.tempOutputURL, preset: job.preset)
            job.status = .compressing
            job.progress = 0
            job.detail = "Compressing"
            job.updatedAt = Date()
            try persistAndPublish(job)
            processLock.sync {
                lastPersistedProgress[job.id] = -1
                closedProgressPersistenceIDs.remove(job.id)
            }

            let result = try runFFmpeg(runtime: runtime, arguments: Array(job.command!.dropFirst()), job: job) { progress, detail, stdout, stderr in
                stdoutLog += stdout
                stderrLog += stderr
                self.publishProgress(job: job, progress: progress, detail: detail)
            }
            ArchiveManifestStore.write(stdoutLog, to: job.logDirectory.appendingPathComponent("ffmpeg-stdout.log"))
            ArchiveManifestStore.write(stderrLog, to: job.logDirectory.appendingPathComponent("ffmpeg-stderr.log"))

            if result.exitCode != 0 {
                if isCancellationRequested(job.id) || result.exitCode == 15 {
                    try finishCancelled(&job)
                    return
                }
                throw NSError(domain: "QuickRecorderArchive", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: "FFmpeg failed. See archive logs for details."])
            }

            job.status = .verifying
            job.progress = 1
            job.detail = "Verifying"
            job.updatedAt = Date()
            try persistAndPublish(job)
            try throwIfCancelled(job.id)
            let validation = try ArchiveTimestampValidator.validate(
                runtime: runtime,
                sourceURL: job.sourceURL,
                outputURL: job.tempOutputURL,
                preset: job.preset,
                ffmpegLog: stderrLog,
                logDirectory: job.logDirectory,
                cancellationRequested: { self.isCancellationRequested(job.id) }
            )
            try throwIfCancelled(job.id)

            if fd.fileExists(atPath: job.outputURL.path) {
                throw NSError(domain: "QuickRecorderArchive", code: 20, userInfo: [NSLocalizedDescriptionKey: "Output already exists."])
            }
            try fd.moveItem(at: job.tempOutputURL, to: job.outputURL)
            job.outputSizeBytes = fileSize(job.outputURL)
            job.validation = validation
            job.status = .completed
            job.detail = "Wrote \(job.outputURL.lastPathComponent)"
            job.updatedAt = Date()
            job.endedAt = Date()
            try persistAndPublish(job)
            SCContext.showNotification(title: "Archive Complete".local, body: String(format: "File saved to: %@".local, job.outputURL.path), id: "quickrecorder.archive.\(UUID().uuidString)")
        } catch ArchiveSubprocessError.cancelled {
            try? finishCancelled(&job)
        } catch FFmpegRuntimeError.missingRuntime {
            finish(&job, status: .runtimeMissing, detail: "FFmpeg runtime missing", error: "Install FFmpeg Runtime")
        } catch {
            finish(&job, status: .failed, detail: "Archive Failed", error: error.localizedDescription)
        }
    }

    private func validateAndPublishRecoveredOutput(_ initialJob: ArchiveJob, candidateURL: URL, moveToFinalOutput: Bool) {
        var job = initialJob
        do {
            try throwIfCancelled(job.id)
            guard fd.fileExists(atPath: job.sourceURL.path) else {
                throw NSError(domain: "QuickRecorderArchive", code: 41, userInfo: [NSLocalizedDescriptionKey: "The source recording is missing."])
            }
            guard fd.fileExists(atPath: candidateURL.path) else {
                throw NSError(domain: "QuickRecorderArchive", code: 42, userInfo: [NSLocalizedDescriptionKey: "The archive output is missing."])
            }
            if moveToFinalOutput && fd.fileExists(atPath: job.outputURL.path) {
                throw NSError(domain: "QuickRecorderArchive", code: 20, userInfo: [NSLocalizedDescriptionKey: "Output already exists."])
            }
            try ensureArchiveOutputIsInactive(candidateURL)
            let runtime = try FFmpegRuntime.resolve()
            let stderrURL = job.logDirectory.appendingPathComponent("ffmpeg-stderr.log")
            let stderrLog = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
            let validation = try ArchiveTimestampValidator.validate(
                runtime: runtime,
                sourceURL: job.sourceURL,
                outputURL: candidateURL,
                preset: job.preset,
                ffmpegLog: stderrLog,
                logDirectory: job.logDirectory,
                cancellationRequested: { self.isCancellationRequested(job.id) }
            )
            try throwIfCancelled(job.id)
            if moveToFinalOutput {
                try fd.moveItem(at: candidateURL, to: job.outputURL)
            }
            job.validation = validation
            job.outputSizeBytes = fileSize(job.outputURL)
            job.status = .completed
            job.detail = "Wrote \(job.outputURL.lastPathComponent)"
            job.updatedAt = Date()
            job.endedAt = Date()
            try persistAndPublish(job)
        } catch ArchiveSubprocessError.cancelled {
            try? finishCancelled(&job)
        } catch {
            finish(&job, status: .interrupted, detail: "Archive recovery needs attention", error: error.localizedDescription)
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
        processLock.sync { processes[job.id] = process }
        if isCancellationRequested(job.id), process.isRunning { process.terminate() }
        process.waitUntilExit()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        processLock.sync {
            processes[job.id] = nil
            closedProgressPersistenceIDs.insert(job.id)
        }

        return ProcessRunResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private func publishProgress(job baseJob: ArchiveJob, progress: Double?, detail: String) {
        DispatchQueue.main.async {
            guard var job = self.jobsByID[baseJob.id], job.status == .compressing else { return }
            job.progress = progress ?? job.progress
            job.detail = detail
            job.updatedAt = Date()
            self.jobsByID[baseJob.id] = job
        }
        guard let progress = progress else { return }
        processLock.sync {
            guard !closedProgressPersistenceIDs.contains(baseJob.id) else { return }
            let last = lastPersistedProgress[baseJob.id] ?? -1
            guard progress >= last + 0.01 else { return }
            lastPersistedProgress[baseJob.id] = progress
            var persistedJob = baseJob
            persistedJob.progress = progress
            persistedJob.detail = detail
            persistedJob.updatedAt = Date()
            persistenceQueue.async {
                do { try ArchiveManifestStore.writeManifest(job: persistedJob) }
                catch { self.reportPersistenceFailure(jobID: baseJob.id, error: error) }
            }
        }
    }

    private func finishCancelled(_ job: inout ArchiveJob) throws {
        try removeTemporaryOutputIfOwned(job)
        _ = processLock.sync { cancelRequestedIDs.remove(job.id) }
        job.status = .cancelled
        job.progress = nil
        job.detail = "Archive cancelled"
        job.errorMessage = nil
        job.updatedAt = Date()
        job.endedAt = Date()
        try persistAndPublish(job)
    }

    private func finish(_ job: inout ArchiveJob, status: ArchiveJobStatus, detail: String, error: String?) {
        job.status = status
        job.detail = detail
        job.errorMessage = error
        job.updatedAt = Date()
        job.endedAt = status.isTerminal ? Date() : nil
        persistOrPublishFailure(job)
        if status == .failed {
            SCContext.showNotification(title: "Archive Failed".local, body: error ?? detail, id: "quickrecorder.archive.error.\(UUID().uuidString)")
        }
    }

    private func persistAndPublish(_ job: ArchiveJob) throws {
        try persistenceQueue.sync {
            try ArchiveManifestStore.writeManifest(job: job)
        }
        publish(job)
    }

    private func persistOrPublishFailure(_ job: ArchiveJob) {
        do {
            try persistAndPublish(job)
        } catch {
            var failed = job
            failed.status = .failed
            failed.detail = "Archive manifest write failed"
            failed.errorMessage = error.localizedDescription
            failed.updatedAt = Date()
            failed.endedAt = Date()
            publish(failed)
        }
    }

    private func publish(_ job: ArchiveJob) {
        DispatchQueue.main.async {
            self.jobsByID[job.id] = job
            if job.isRunning {
                self.activeJobIDBySource[job.sourceURL.path] = job.id
            } else if self.activeJobIDBySource[job.sourceURL.path] == job.id {
                self.activeJobIDBySource[job.sourceURL.path] = nil
            }
            if self.quitAfterSourcePaths.contains(job.sourceURL.path), !job.isRunning {
                self.quitAfterSourcePaths.remove(job.sourceURL.path)
                NSApp.terminate(nil)
            }
            self.drainCompletionWaitersIfIdle()
        }
    }

    private func drainCompletionWaitersIfIdle() {
        guard !hasRunningJobs, !completionWaiters.isEmpty else { return }
        let waiters = completionWaiters
        completionWaiters.removeAll()
        waiters.forEach { $0() }
    }

    private func reportPersistenceFailure(jobID: UUID, error: Error) {
        DispatchQueue.main.async {
            guard var job = self.jobsByID[jobID] else { return }
            job.status = .failed
            job.detail = "Archive manifest write failed"
            job.errorMessage = error.localizedDescription
            job.updatedAt = Date()
            job.endedAt = Date()
            self.jobsByID[jobID] = job
            self.drainCompletionWaitersIfIdle()
        }
    }

    private func restorePersistedJobs() {
        let loaded = ArchiveManifestStore.loadJobs()
        manifestLoadIssues = loaded.issues
        for var job in loaded.jobs {
            if job.status == .cancelled {
                do {
                    try ensureTemporaryOutputIsInactive(job)
                    try removeTaskDirectory(job.logDirectory, jobID: job.id)
                } catch {
                    manifestLoadIssues.append(
                        ArchiveManifestLoadIssue(
                            manifestURL: job.logDirectory.appendingPathComponent("manifest.json"),
                            message: error.localizedDescription
                        )
                    )
                }
                continue
            }
            let sourceExists = fd.fileExists(atPath: job.sourceURL.path)
            let outputExists = fd.fileExists(atPath: job.outputURL.path)
            let temporaryOutputExists = fd.fileExists(atPath: job.tempOutputURL.path)
            if !sourceExists && !outputExists && !temporaryOutputExists {
                do {
                    try removeTaskDirectory(job.logDirectory, jobID: job.id)
                } catch {
                    manifestLoadIssues.append(
                        ArchiveManifestLoadIssue(
                            manifestURL: job.logDirectory.appendingPathComponent("manifest.json"),
                            message: error.localizedDescription
                        )
                    )
                }
                continue
            }
            if job.status.becomesInterruptedWithoutWorker {
                job.status = .interrupted
                job.progress = nil
                job.detail = "Archive interrupted when QuickRecorder stopped"
                job.errorMessage = "Review this archive before restarting it."
                job.updatedAt = Date()
                do {
                    try ArchiveManifestStore.writeManifest(job: job)
                } catch {
                    manifestLoadIssues.append(ArchiveManifestLoadIssue(manifestURL: job.logDirectory.appendingPathComponent("manifest.json"), message: error.localizedDescription))
                }
            }
            jobsByID[job.id] = job
        }
    }

    private func setImmediateFailure(sourceURL: URL, message: String) {
        do {
            let id = UUID()
            let preset = AV1ArchivePreset.current
            let logDirectory = try ArchiveManifestStore.createJobDirectory(id: id)
            let now = Date()
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
                command: nil,
                validation: nil,
                startedAt: now,
                updatedAt: now,
                endedAt: now
            )
            try persistAndPublish(job)
        } catch {
            print(message)
        }
    }

    private func removeTemporaryOutputIfOwned(_ job: ArchiveJob) throws {
        guard fd.fileExists(atPath: job.tempOutputURL.path) else { return }
        guard ArchivePathSafety.isTaskOwned(job.tempOutputURL, jobsRoot: ArchivePaths.jobsDirectory, jobID: job.id) else {
            throw NSError(domain: "QuickRecorderArchive", code: 43, userInfo: [NSLocalizedDescriptionKey: "Refusing to remove an archive file outside its task directory."])
        }
        try fd.removeItem(at: job.tempOutputURL)
    }

    private func removeTaskDirectory(_ directory: URL, jobID: UUID) throws {
        let expectedDirectory = ArchivePaths.jobsDirectory
            .appendingPathComponent(jobID.uuidString, isDirectory: true)
            .standardizedFileURL
        guard directory.standardizedFileURL.path == expectedDirectory.path else {
            throw NSError(
                domain: "QuickRecorderArchive",
                code: 47,
                userInfo: [NSLocalizedDescriptionKey: "Refusing to remove a recovery record outside its task directory."]
            )
        }
        guard fd.fileExists(atPath: directory.path) else { return }
        try fd.removeItem(at: directory)
    }

    private func ensureTemporaryOutputIsInactive(_ job: ArchiveJob) throws {
        guard fd.fileExists(atPath: job.tempOutputURL.path) else { return }
        try ensureArchiveOutputIsInactive(job.tempOutputURL)
    }

    private func ensureArchiveOutputIsInactive(_ url: URL) throws {
        let result = try FFmpegRuntime.run(
            URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-t", "--", url.path],
            timeout: 5
        )
        if result.exitCode == 0 && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NSError(
                domain: "QuickRecorderArchive",
                code: 45,
                userInfo: [NSLocalizedDescriptionKey: "Another process is still writing this archive. Wait for it to stop before recovery."]
            )
        }
    }

    private func throwIfCancelled(_ jobID: UUID) throws {
        if isCancellationRequested(jobID) {
            throw ArchiveSubprocessError.cancelled
        }
    }

    private func isCancellationRequested(_ jobID: UUID) -> Bool {
        processLock.sync { cancelRequestedIDs.contains(jobID) }
    }

    private func fileSize(_ url: URL) -> Int64 {
        let attrs = try? fd.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? Int64 ?? 0
    }
}
