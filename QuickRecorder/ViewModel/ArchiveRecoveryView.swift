import SwiftUI
import AppKit
import ArchiveJobCore

struct ArchiveRecoveryView: View {
    @ObservedObject private var service = ArchiveCompressionService.shared
    @State private var showingClearConfirmation = false

    private var visibleRecordIDs: [UUID] {
        service.recoveryJobs.map(\.id) + service.manifestLoadIssues.map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Interrupted Archives".local)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear All Recovery Records".local, systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(visibleRecordIDs.isEmpty)
            }
            Text("QuickRecorder found archive jobs that did not finish. Review them before restarting compression.".local)
                .font(.callout)
                .foregroundColor(.secondary)

            if let cleanupError = service.recoveryCleanupError {
                Label(cleanupError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if service.recoveryJobs.isEmpty && service.manifestLoadIssues.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.green)
                    Text("No interrupted archives remain.".local)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(service.recoveryJobs) { job in
                            recoveryRow(job)
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .opacity.combined(with: .scale(scale: 0.97))
                                ))
                        }
                        ForEach(service.manifestLoadIssues) { issue in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Archive manifest needs attention".local)
                                    .fontWeight(.semibold)
                                Text(issue.manifestURL.deletingLastPathComponent().lastPathComponent)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(issue.message)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                Button(role: .destructive) {
                                    withAnimation {
                                        service.removeManifestLoadIssue(issueID: issue.id)
                                    }
                                } label: {
                                    Label("Remove Recovery Record".local, systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(8)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 320)
        .animation(.easeInOut(duration: 0.2), value: visibleRecordIDs)
        .confirmationDialog(
            "Clear All Recovery Records?".local,
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Recovery Records".local, role: .destructive) {
                withAnimation {
                    service.clearAllRecoveryRecords()
                }
            }
            Button("Cancel".local, role: .cancel) {}
        } message: {
            Text("This removes recovery records, logs, and task-owned temporary files. Original recordings and completed archives are not deleted.".local)
        }
    }

    private func recoveryRow(_ job: ArchiveJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(job.sourceURL.lastPathComponent)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(job.errorMessage ?? job.detail)
                .font(.caption)
                .foregroundColor(.secondary)
            if !FileManager.default.fileExists(atPath: job.sourceURL.path) {
                Label("The original recording no longer exists. This task cannot be restarted.".local, systemImage: "doc.badge.xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                switch service.recoveryDisposition(for: job) {
                case .validateTemporaryOutput:
                    Button("Validate Temporary Archive".local) {
                        service.recoverTemporaryOutput(jobID: job.id)
                    }
                case .validateFinalOutput:
                    Button("Validate Recovered Archive".local) {
                        service.recoverFinalOutput(jobID: job.id)
                    }
                case .restartEncoding, .completedOutputMissing:
                    Button("Restart Compression".local) {
                        service.restart(jobID: job.id)
                    }
                case .sourceMissing, .outputConflict, .alreadyCompleted, .noAction:
                    EmptyView()
                }
                Button(role: .destructive) {
                    withAnimation {
                        service.removeRecoveryJob(jobID: job.id)
                    }
                } label: {
                    Label("Remove Recovery Record".local, systemImage: "trash")
                }
                .buttonStyle(.bordered)
                Spacer()
                if let revealURL = revealURL(for: job) {
                    Button("Reveal in Finder".local) {
                        NSWorkspace.shared.activateFileViewerSelecting([revealURL])
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private func revealURL(for job: ArchiveJob) -> URL? {
        if FileManager.default.fileExists(atPath: job.sourceURL.path) {
            return job.sourceURL
        }
        if FileManager.default.fileExists(atPath: job.outputURL.path) {
            return job.outputURL
        }
        return nil
    }
}
