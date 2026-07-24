import SwiftUI

struct ArchiveSettingsSection: View {
    @AppStorage("autoCreateAV1ArchiveAfterRecording") private var autoCreateAV1ArchiveAfterRecording: Bool = false
    @AppStorage("archiveAV1CRF") private var archiveAV1CRF: Int = 56
    @AppStorage("archiveAV1SVTPreset") private var archiveAV1SVTPreset: Int = 8
    @AppStorage("archiveAV1GOP") private var archiveAV1GOP: Int = 270
    @AppStorage("archiveAV1AudioMode") private var archiveAV1AudioMode: AV1ArchiveAudioMode = .aacMono64k
    @AppStorage("archiveAllowDeveloperFFmpegRuntime") private var archiveAllowDeveloperFFmpegRuntime: Bool = false
    @AppStorage("archiveReplaceSourceAfterValidation") private var archiveReplaceSourceAfterValidation: Bool = false
    @State private var runtimeStatus: String = "Checking..."

    var body: some View {
        SGroupBox(label: "AV1 Archive") {
            SToggle("Auto-compress recordings to AV1", isOn: $autoCreateAV1ArchiveAfterRecording, tips: "After the HEVC master is saved, QuickRecorder will create a verified AV1 archive in the background.")
            SDivider()
            SSteper("CRF", value: $archiveAV1CRF, min: 0, max: 63, tips: "CRF 56 is the current safe lecture archive default. Lower values are larger and higher quality.")
            SDivider()
            SSteper("SVT Preset", value: $archiveAV1SVTPreset, min: 0, max: 13, tips: "Preset 8 is the current speed/size default for post-recording archives.")
            SDivider()
            SSteper("GOP", value: $archiveAV1GOP, min: 1, max: 2000)
            SDivider()
            SPicker("Archive Audio", selection: $archiveAV1AudioMode) {
                ForEach(AV1ArchiveAudioMode.allCases) { mode in
                    Text(mode.displayName.local).tag(mode)
                }
            }
            SDivider()
            SItem(label: "FFmpeg Runtime") {
                Text(runtimeStatus.local)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Install FFmpeg Runtime".local) {
                    ArchiveCompressionService.shared.installRuntime()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        refreshRuntimeStatus()
                    }
                }
            }
            SDivider()
            SToggle("Use developer FFmpeg fallback", isOn: $archiveAllowDeveloperFFmpegRuntime, tips: "Developer fallback checks common Homebrew paths only when the bundled runtime package is unavailable.")
            SDivider()
            SToggle("Replace source after strict validation", isOn: $archiveReplaceSourceAfterValidation, tips: "Disabled for now. Source replacement requires HEVC backup and rollback.")
                .disabled(true)
        }
        .onAppear { refreshRuntimeStatus() }
    }

    private func refreshRuntimeStatus() {
        DispatchQueue.global(qos: .utility).async {
            let status: String
            do {
                let runtime = try FFmpegRuntime.resolve()
                status = runtime.description
            } catch {
                status = "FFmpeg runtime missing"
            }
            DispatchQueue.main.async {
                runtimeStatus = status
            }
        }
    }
}
