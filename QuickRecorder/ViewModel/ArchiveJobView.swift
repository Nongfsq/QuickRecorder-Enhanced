import SwiftUI

struct ArchiveJobView: View {
    let sourceURL: URL
    @ObservedObject private var service = ArchiveCompressionService.shared
    @State private var nsWindow: NSWindow?

    private var job: ArchiveJob? {
        service.job(for: sourceURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            statusBody
            Spacer(minLength: 0)
            actionBar
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 260)
        .background(WindowAccessor(onWindowOpen: { window in
            nsWindow = window
            window?.styleMask.insert(.resizable)
        }))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox")
                .font(.system(size: 24, weight: .semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text("AV1 Archive".local)
                    .font(.headline)
                Text(sourceURL.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var statusBody: some View {
        if let job = job {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(job.status.displayName.local)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    if let sourceSize = job.sourceSizeBytes {
                        Text(byteString(sourceSize))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                if job.status == .compressing || job.status == .verifying || job.status == .cancelling {
                    ProgressView(value: job.progress)
                }
                Text(job.detail.local)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let error = job.errorMessage {
                    Text(error.local)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if job.status == .completed {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "File saved to: %@".local, job.outputURL.path))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let sourceSize = job.sourceSizeBytes, let outputSize = job.outputSizeBytes, sourceSize > 0 {
                            let saved = max(0, 1 - Double(outputSize) / Double(sourceSize))
                            Text(String(format: "Saved %.1f%%".local, saved * 100))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Text(String(format: "Logs: %@".local, job.logDirectory.path))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Create AV1 Archive".local)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Create a compact AV1 archive while preserving the HEVC master.".local)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var actionBar: some View {
        HStack {
            Button("Reveal in Finder".local) {
                reveal()
            }
            if let job = job, job.status == .completed {
                Button("Open Archive".local) {
                    NSWorkspace.shared.open(job.outputURL)
                }
            }
            Spacer()
            if let job = job, job.isRunning {
                if job.status == .cancelling {
                    Button("Cancelling".local) {}
                        .disabled(true)
                } else {
                    Button("Cancel Archive".local) {
                        service.cancel(jobID: job.id)
                    }
                }
            } else if let job = job, job.status == .interrupted {
                if FileManager.default.fileExists(atPath: job.tempOutputURL.path) {
                    Button("Validate Temporary Archive".local) {
                        service.recoverTemporaryOutput(jobID: job.id)
                    }
                }
                Button("Restart Compression".local) {
                    service.restart(jobID: job.id)
                }
            } else {
                Button("Install FFmpeg Runtime".local) {
                    service.installRuntime()
                }
                Button("Create AV1 Archive".local) {
                    service.startArchive(for: sourceURL)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func reveal() {
        if let job = job, job.status == .completed {
            NSWorkspace.shared.activateFileViewerSelecting([job.outputURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([sourceURL])
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
