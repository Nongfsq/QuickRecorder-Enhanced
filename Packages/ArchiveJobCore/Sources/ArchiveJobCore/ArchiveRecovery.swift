import Foundation

public enum ArchiveRecoveryDisposition: Equatable {
    case alreadyCompleted
    case completedOutputMissing
    case validateFinalOutput
    case validateTemporaryOutput
    case restartEncoding
    case sourceMissing
    case outputConflict
    case noAction
}

public enum ArchiveRecoveryClassifier {
    public static func classify(
        manifest: ArchiveJobManifest,
        sourceExists: Bool,
        outputExists: Bool,
        temporaryOutputExists: Bool
    ) -> ArchiveRecoveryDisposition {
        classify(
            status: manifest.status,
            sourceExists: sourceExists,
            outputExists: outputExists,
            temporaryOutputExists: temporaryOutputExists
        )
    }

    public static func classify(
        status: ArchiveJobState,
        sourceExists: Bool,
        outputExists: Bool,
        temporaryOutputExists: Bool
    ) -> ArchiveRecoveryDisposition {
        if status == .cancelled {
            return .noAction
        }
        if status == .completed {
            if outputExists { return .alreadyCompleted }
            return sourceExists ? .completedOutputMissing : .sourceMissing
        }
        guard sourceExists else {
            return outputExists ? .outputConflict : .sourceMissing
        }
        if outputExists {
            return status.becomesInterruptedWithoutWorker || status == .interrupted
                ? .validateFinalOutput
                : .outputConflict
        }
        if temporaryOutputExists { return .validateTemporaryOutput }
        if status.becomesInterruptedWithoutWorker || status == .interrupted {
            return .restartEncoding
        }
        return .noAction
    }
}

public enum ArchivePathSafety {
    public static func isTaskOwned(_ candidate: URL, jobsRoot: URL, jobID: UUID) -> Bool {
        let taskRoot = jobsRoot
            .appendingPathComponent(jobID.uuidString, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let resolvedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = taskRoot.path.hasSuffix("/") ? taskRoot.path : taskRoot.path + "/"
        return resolvedCandidate.path.hasPrefix(rootPath)
    }
}
