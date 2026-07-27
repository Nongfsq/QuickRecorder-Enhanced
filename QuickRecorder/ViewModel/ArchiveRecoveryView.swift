import SwiftUI
import AppKit
import ArchiveJobCore

struct ArchiveRecoveryView: View {
    @ObservedObject private var service = ArchiveCompressionService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Interrupted Archives".local)
                .font(.title2)
                .fontWeight(.semibold)
            Text("QuickRecorder found archive jobs that did not finish. Review them before restarting compression.".local)
                .font(.callout)
                .foregroundColor(.secondary)

            if service.recoveryJobs.isEmpty && service.manifestLoadIssues.isEmpty {
                Text("No interrupted archives remain.".local)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(service.recoveryJobs) { job in
                            recoveryRow(job)
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
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 320)
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
                Button("Abandon Archive Job".local) {
                    service.abandon(jobID: job.id)
                }
                Spacer()
                Button("Reveal in Finder".local) {
                    NSWorkspace.shared.activateFileViewerSelecting([job.sourceURL])
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }
}
