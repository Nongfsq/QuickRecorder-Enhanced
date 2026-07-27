//
//  SCContext.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/16.
//

import AVFAudio
import AVFoundation
import Foundation
import ScreenCaptureKit
import UserNotifications
import SwiftLAME
import SwiftUI
import AECAudioStream
import RecordingDomain

class SCContext {
    private static var session: RecordingSessionCoordinator { AppDelegate.shared.recordingSession }
    private static var captureOwner: RecordingCaptureContextOwner { session.capture }
    private static var deviceOwner: RecordingDeviceContextOwner { session.device }
    private static var finalizationOwner: RecordingFinalizationContextOwner { session.finalization }
    static var trimingList: [URL] {
        get { finalizationOwner.trimmingList }
        set { finalizationOwner.trimmingList = newValue }
    }
    private static var mediaOwner: RecordingSessionMediaOwner { AppDelegate.shared.recordingSession.media }
    static var firstFrame: CMSampleBuffer? {
        get { mediaOwner.firstFrame }
        set { mediaOwner.firstFrame = newValue }
    }
    static var autoStop = 0
    static var recordCam: String {
        get { deviceOwner.cameraIdentifier }
        set { deviceOwner.cameraIdentifier = newValue }
    }
    static var recordDevice: String {
        get { deviceOwner.deviceIdentifier }
        set { deviceOwner.deviceIdentifier = newValue }
    }
    static var captureSession: AVCaptureSession! {
        get { deviceOwner.captureSession }
        set { deviceOwner.captureSession = newValue }
    }
    static var previewSession: AVCaptureSession! {
        get { deviceOwner.previewSession }
        set { deviceOwner.previewSession = newValue }
    }
    static var frameCache: CMSampleBuffer? {
        get { deviceOwner.frameCache }
        set { deviceOwner.frameCache = newValue }
    }
    static var filter: SCContentFilter? {
        get { captureOwner.filter }
        set { captureOwner.filter = newValue }
    }
    static var isMagnifierEnabled = false
    static var saveFrame = false
    static var isPaused: Bool {
        get { mediaOwner.isPaused }
        set { mediaOwner.isPaused = newValue }
    }
    static var isSkipFrame = false
    static var lastPTS: CMTime? {
        get { mediaOwner.lastPTS }
        set { mediaOwner.lastPTS = newValue }
    }
    static var lastVideoPTS: CMTime? {
        get { mediaOwner.lastVideoPTS }
        set { mediaOwner.lastVideoPTS = newValue }
    }
    static var adaptiveVFRSkippedFrames: Int {
        get { mediaOwner.adaptiveVFRSkippedFrames }
        set { mediaOwner.adaptiveVFRSkippedFrames = newValue }
    }
    static var screenArea: NSRect? {
        get { captureOwner.screenArea }
        set { captureOwner.screenArea = newValue }
    }
    static let audioEngine = AVAudioEngine()
    static let AECEngine = AECAudioStream(sampleRate: 48000)
    static var microphoneNoiseReductionPipeline: MicrophoneNoiseReductionPipeline?
    static var backgroundColor: CGColor = CGColor.black
    static var filePath: String! {
        get { finalizationOwner.primaryPath }
        set { finalizationOwner.primaryPath = newValue }
    }
    static var filePath1: String! {
        get { finalizationOwner.systemAudioPath }
        set { finalizationOwner.systemAudioPath = newValue }
    }
    static var filePath2: String! {
        get { finalizationOwner.microphonePath }
        set { finalizationOwner.microphonePath = newValue }
    }
    static var audioFile: AVAudioFile? {
        get { finalizationOwner.systemAudioFile }
        set { finalizationOwner.systemAudioFile = newValue }
    }
    static var audioFile2: AVAudioFile? {
        get { finalizationOwner.microphoneAudioFile }
        set { finalizationOwner.microphoneAudioFile = newValue }
    }
    static var vW: AVAssetWriter! {
        get { mediaOwner.writer }
    }
    static var vwInput: AVAssetWriterInput! {
        get { mediaOwner.videoInput }
    }
    static var awInput: AVAssetWriterInput! {
        get { mediaOwner.systemAudioInput }
    }
    static var micInput: AVAssetWriterInput! {
        get { mediaOwner.microphoneInput }
    }
    static var startTime: Date? {
        get { mediaOwner.startTime }
        set { mediaOwner.startTime = newValue }
    }
    static var timePassed: TimeInterval {
        get { finalizationOwner.elapsedTime }
        set { finalizationOwner.elapsedTime = newValue }
    }
    static var partialQMAPackagePath: String? {
        get { finalizationOwner.partialPackagePath }
        set { finalizationOwner.partialPackagePath = newValue }
    }
    static var stream: SCStream! {
        get { captureOwner.stream }
        set { captureOwner.stream = newValue }
    }
    static var screen: SCDisplay? {
        get { captureOwner.screen }
        set { captureOwner.screen = newValue }
    }
    static var window: [SCWindow]? {
        get { captureOwner.windows }
        set { captureOwner.windows = newValue }
    }
    static var application: [SCRunningApplication]? {
        get { captureOwner.applications }
        set { captureOwner.applications = newValue }
    }
    static var streamType: StreamType? {
        get { captureOwner.mode }
        set { captureOwner.mode = newValue }
    }
    static var availableContent: SCShareableContent? {
        get { captureOwner.availableContent }
        set { captureOwner.availableContent = newValue }
    }
    static let excludedApps = ["", "com.apple.dock", "com.apple.screencaptureui", "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.systemuiserver", "com.apple.WindowManager", "dev.mnpn.Azayaka", "com.gaosun.eul", "com.pointum.hazeover", "net.matthewpalmer.Vanilla", "com.dwarvesv.minimalbar", "com.bjango.istatmenus.status"]
    
    static func updateAvailableContentSync() -> SCShareableContent? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: SCShareableContent? = nil

        updateAvailableContent { content in
            result = content
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }
    
    private static func updateAvailableContent(completion: @escaping (SCShareableContent?) -> Void) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            if let error = error {
                availableContent = nil
                switch error {
                case SCStreamError.userDeclined:
                    // Startup permission checks must be single-shot. Retrying
                    // here caused macOS to show the same privacy prompt in an
                    // unbounded loop when ScreenCaptureKit returned declined.
                    print("Screen recording permission is unavailable.".local)
                default:
                    print("Error: failed to fetch available content: ".local, error.localizedDescription)
                }
                completion(nil)
                return
            }

            availableContent = content
            if let displays = content?.displays, !displays.isEmpty {
                completion(content) // 返回成功获取的 content
            } else {
                print("There needs to be at least one display connected!".local)
                completion(nil) // 如果没有显示器连接，则返回 nil
            }
        }
    }
    
    static func updateAvailableContent(completion: @escaping () -> Void) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
            if let error = error {
                switch error {
                case SCStreamError.userDeclined: requestPermissions()
                default: print("Error: failed to fetch available content: ".local, error.localizedDescription)
                }
                return
            }
            availableContent = content
            assert(availableContent?.displays.isEmpty != nil, "There needs to be at least one display connected!".local)
            completion()
        }
    }
    
    static func getSelf() -> SCRunningApplication? {
        return SCContext.availableContent!.applications.first(where: { Bundle.main.bundleIdentifier == $0.bundleIdentifier })
    }
    
    static func getSelfWindows() -> [SCWindow]? {
        return SCContext.availableContent!.windows.filter( {
            guard let title = $0.title else { return false }
            return $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            && title != "Mouse Pointer".local
            && title != "Screen Magnifier".local
            && title != "Camera Overlayer".local
            && title != "iDevice Overlayer".local
        })
    }
    
    static func getApps(isOnScreen: Bool = true, hideSelf: Bool = true) -> [SCRunningApplication] {
        var apps = [SCRunningApplication]()
        for app in getWindows(isOnScreen: isOnScreen, hideSelf: hideSelf).map({ $0.owningApplication }) {
            if !apps.contains(app!) { apps.append(app!) }
        }
        if hideSelf && ud.bool(forKey: "hideSelf") { apps = apps.filter({$0.bundleIdentifier != Bundle.main.bundleIdentifier}) }
        return apps
    }
    
    static func getWindows(isOnScreen: Bool = true, hideSelf: Bool = true) -> [SCWindow] {
        var windows = [SCWindow]()
        windows = availableContent!.windows.filter {
            guard let app =  $0.owningApplication,
                  let title = $0.title else {//, !title.isEmpty else {
                return false
            }
            return !excludedApps.contains(app.bundleIdentifier)
            && !title.contains("Item-0")
            && title != "Window"
            && $0.frame.width > 40
            && $0.frame.height > 40
        }
        if isOnScreen { windows = windows.filter({$0.isOnScreen == true}) }
        if hideSelf && ud.bool(forKey: "hideSelf") { windows = windows.filter({$0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier}) }
        return windows
    }
    
    static func getAppIcon(_ app: SCRunningApplication) -> NSImage? {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 69, height: 69)
            return icon
        }
        let icon = NSImage(systemSymbolName: "questionmark.app.dashed", accessibilityDescription: "blank icon")
        icon!.size = NSSize(width: 69, height: 69)
        return icon
    }
    
    static func getScreenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let screenWithMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
        return screenWithMouse
    }
    
    static func getSCDisplayWithMouse() -> SCDisplay? {
        if let displays = availableContent?.displays {
            for display in displays {
                if let currentDisplayID = getScreenWithMouse()?.displayID {
                    if display.displayID == currentDisplayID {
                        return display
                    }
                }
            }
        }
        return nil
    }
    
    static func getFilePath(capture: Bool = false) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "y-MM-dd HH.mm.ss"
        let outputDirectory = AppDelegate.shared.recordingSession.request?.settings.outputDirectory
            ?? ud.string(forKey: "saveDirectory")!
        return outputDirectory + (capture ? "/Capturing at ".local : "/Recording at ".local) + dateFormatter.string(from: Date())
    }
    
    static func getAudioChannelCount() -> Int {
        if let channels = AppDelegate.shared.recordingSession.request?.settings.audioChannels.rawValue {
            return channels
        }
        return ud.integer(forKey: "audioChannels") == AudioChannels.mono.rawValue
            ? AudioChannels.mono.rawValue
            : AudioChannels.stereo.rawValue
    }

    static func makeAudioPCMBufferForConfiguredChannels(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let targetChannelCount = AVAudioChannelCount(getAudioChannelCount())
        guard buffer.format.channelCount != targetChannelCount else { return buffer }
        return buffer.converted(toChannelCount: targetChannelCount) ?? buffer
    }

    static func makeAudioSampleBufferForConfiguredChannels(_ buffer: AVAudioPCMBuffer, presentationTimeStamp: CMTime? = nil) -> CMSampleBuffer? {
        makeAudioPCMBufferForConfiguredChannels(buffer).makeSampleBuffer(presentationTimeStamp: presentationTimeStamp)
    }

    static func makeAudioSampleBufferForConfiguredChannels(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        if let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
           Int(description.mChannelsPerFrame) == getAudioChannelCount() {
            return sampleBuffer
        }
        guard let pcmBuffer = sampleBuffer.asPCMBuffer else { return sampleBuffer }
        return makeAudioSampleBufferForConfiguredChannels(pcmBuffer, presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    static func updateAudioSettings(format: String? = nil, rate: Int = 48000, channels: Int? = nil) -> [String : Any] {
        let activeSettings = AppDelegate.shared.recordingSession.request?.settings
        let resolvedFormat = format ?? activeSettings?.audioFormat.rawValue ?? ud.string(forKey: "audioFormat") ?? ""
        var audioSettings: [String : Any] = [AVSampleRateKey : rate, AVNumberOfChannelsKey : channels ?? getAudioChannelCount()] // reset audioSettings
        var bitRate = (activeSettings?.audioQuality.rawValue ?? ud.integer(forKey: "audioQuality")) * 1000
        if rate < 44100 { bitRate = min(64000, bitRate / 2) }
        switch resolvedFormat {
        case AudioFormat.mp3.rawValue: fallthrough
        case AudioFormat.aac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] = bitRate
        case AudioFormat.alac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatAppleLossless
            audioSettings[AVEncoderBitDepthHintKey] = 16
        case AudioFormat.flac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatFLAC
        case AudioFormat.opus.rawValue:
            let videoFormat = activeSettings?.videoFormat.rawValue ?? ud.string(forKey: "videoFormat")
            audioSettings[AVFormatIDKey] = videoFormat != VideoFormat.mp4.rawValue ? kAudioFormatOpus : kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] =  bitRate
        default:
            assertionFailure("unknown audio format while setting audio settings: ".local + (ud.string(forKey: "audioFormat") ?? "[no defaults]".local))
        }
        return audioSettings
    }
    
    static func getBackgroundColor() -> CGColor {
        guard let color = AppDelegate.shared.recordingSession.request?.settings.background.rawValue
            ?? ud.string(forKey: "background") else { return CGColor.black  }
        if color == BackgroundType.wallpaper.rawValue { return CGColor.black }
        switch color {
            case "clear": backgroundColor = CGColor.clear
            case "black": backgroundColor = CGColor.black
            case "white": backgroundColor = CGColor.white
            case "gray": backgroundColor = NSColor.systemGray.cgColor
            case "yellow": backgroundColor = NSColor.systemYellow.cgColor
            case "orange": backgroundColor = NSColor.systemOrange.cgColor
            case "green": backgroundColor = NSColor.systemGreen.cgColor
            case "blue": backgroundColor = NSColor.systemBlue.cgColor
            case "red": backgroundColor = NSColor.systemRed.cgColor
            default: backgroundColor = ud.cgColor(forKey: "userColor") ?? CGColor.black
        }
        return backgroundColor
    }
    
    static func performMicCheck() async {
        guard ud.bool(forKey: "recordMic") == true else { return }
        if await AVCaptureDevice.requestAccess(for: .audio) { return }

        ud.setValue(false, forKey: "recordMic")
        DispatchQueue.main.async {
            let alert = createAlert(title: "Permission Required",
                                                       message: "QuickRecorder needs permission to record your microphone.",
                                                       button1: "Open Settings",
                                                       button2: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
        }
    }
    
    private static func requestPermissions() {
        DispatchQueue.main.async {
            let alert = createAlert(title: "Permission Required",
                                                       message: "QuickRecorder needs screen recording permissions, even if you only intend on recording audio.",
                                                       button1: "Open Settings",
                                                       button2: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
            NSApp.terminate(self)
        }
    }
    
    static func requestCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized, .restricted, .notDetermined:
            break
        case .denied:
            DispatchQueue.main.async {
                let alert = createAlert(title: "Permission Required",
                                                           message: "QuickRecorder needs this permission to record your camera or mobile device.",
                                                           button1: "Open Settings",
                                                           button2: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            }
        @unknown default:
            break
        }
    }
    
    static func getWallpaper(_ display: SCDisplay) -> NSImage? {
        guard let screen = display.nsScreen else { return nil }
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        do {
            var wallpaper: NSImage?
            try wallpaper = NSImage(data: Data(contentsOf: url))
            if let w = wallpaper { return w }
        } catch {
            print("load wallpaper error: \(error)")
        }
        return nil
    }
    
    static func getRecordingSize() -> String {
        do {
            let fileAttr = try fd.attributesOfItem(atPath: filePath)
            let byteFormat = ByteCountFormatter()
            byteFormat.allowedUnits = [.useMB]
            byteFormat.countStyle = .file
            return byteFormat.string(fromByteCount: fileAttr[FileAttributeKey.size] as! Int64)
        } catch {
            print(String(format: "failed to fetch file for size indicator: %@".local, error.localizedDescription))
        }
        return "Unknown".local
    }
    
    static func getRecordingLength() -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        if isPaused { return formatter.string(from: timePassed) ?? "Unknown".local }
        timePassed = Date.now.timeIntervalSince(startTime ?? Date.now)
        return formatter.string(from: timePassed) ?? "Unknown".local
    }
    
    static func isCameraRunning() -> Bool {
        var preview = false
        var capture = false
        if let session = previewSession { preview = session.isRunning }
        if let session = captureSession { capture = session.isRunning }
        return (preview || capture)
    }
    
    static func pauseRecording() {
        let paused = mediaOwner.togglePaused()
        if !paused { startTime = Date.now.addingTimeInterval(-1) - timePassed }
        if paused {
            AppDelegate.shared.recordingSession.markPaused()
        } else {
            AppDelegate.shared.recordingSession.markResumed()
        }
        PopoverState.shared.isPaused = paused
    }
    
    static func stopRecording(completion: (() -> Void)? = nil) {
        let activeRequest = AppDelegate.shared.recordingSession.request
        guard AppDelegate.shared.recordingSession.beginStopping(completion: completion) else { return }
        guard let activeRequest else {
            AppDelegate.shared.recordingSession.fail("Recording request is unavailable during finalization.")
            return
        }
        let settings = activeRequest.settings
        let recordsMicrophone = settings.recordsMicrophone
        let recordsSystemAudio = settings.recordsSystemAudio
        let remuxesAudio = settings.remuxesAudio
        let audioFormat = settings.audioFormat
        let audioQuality = settings.audioQuality
        let finalizingStreamType = streamType
        let activeStream = stream
        guard let primaryPath = filePath else {
            AppDelegate.shared.recordingSession.fail("Recording output path is unavailable during finalization.")
            return
        }
        let primaryURL = primaryPath.url
        let auxiliaryAudioURL = filePath1?.url
        guard AppDelegate.shared.recordingSession.beginFinalizing() else {
            AppDelegate.shared.recordingSession.fail("Unable to begin recording finalization.")
            return
        }

        Task {
            if settings.preventsSleep { SleepPreventer.shared.allowSleep() }
            autoStop = 0
            lastPTS = nil
            lastVideoPTS = nil
            adaptiveVFRSkippedFrames = 0
            recordCam = ""
            recordDevice = ""
            isMagnifierEnabled = false
            await MainActor.run {
                mousePointer.orderOut(nil)
                screenMagnifier.orderOut(nil)
                AppDelegate.shared.stopGlobalMouseMonitor()
                if let window = NSApp.windows.first(where: { $0.title == "Area Overlayer".local }) {
                    window.close()
                }
            }
            if let activeStream { try? await activeStream.stopCapture() }
            stream = nil
            if recordsMicrophone {
                AudioRecorder.shared.stop()
                audioEngine.inputNode.removeTap(onBus: 0)
                audioEngine.stop()
                if settings.enablesAEC { try? AECEngine.stopAudioUnit() }
                mediaOwner.performSample { flushMicrophoneNoiseReduction() }
            }
            var writerResult: RecordingSessionMediaOwner.WriterResult?
            if finalizingStreamType != .systemaudio {
                writerResult = await mediaOwner.finishWriting(
                    markVideoInput: true,
                    markSystemAudioInput: true,
                    markMicrophoneInput: recordsMicrophone
                )
            } else if recordsMicrophone {
                writerResult = await mediaOwner.finishWriting(
                    markVideoInput: false,
                    markSystemAudioInput: false,
                    markMicrophoneInput: true
                )
            } else {
                mediaOwner.stopAcceptingSamples()
            }
        
        DispatchQueue.main.async {
            controlPanel.close()
            if isCameraRunning() {
                if camWindow.isVisible { camWindow.close() }
                if deviceWindow.isVisible { deviceWindow.close() }
                if let preview = previewSession { preview.stopRunning() }
                if let capture = captureSession { capture.stopRunning() }
            }
        }
        
        audioFile = nil // close audio file
        audioFile2 = nil // close audio file2
        mediaOwner.discardWriter()

        let finalize: (FinalizationOutcome) -> Void = { outcome in
            DispatchQueue.main.async {
                completeFinalization(outcome)
            }
        }

        if finalizingStreamType != .systemaudio, writerResult?.status != .completed {
            let message = writerResult?.error?.localizedDescription ?? "Video writer did not complete"
            finalize(.failure(RecordingFailure(stage: .writer, message: message, retainedURL: primaryURL)))
        } else if finalizingStreamType == .systemaudio, recordsMicrophone, writerResult?.status != .completed {
            let message = writerResult?.error?.localizedDescription ?? "Microphone writer did not complete"
            finalize(.failure(RecordingFailure(stage: .writer, message: message, retainedURL: primaryURL)))
        } else if finalizingStreamType == .systemaudio {
            if audioFormat == .mp3 && !recordsMicrophone {
                Task {
                    let outputURL = primaryURL.deletingPathExtension().appendingPathExtension("mp3")
                    do {
                        guard let auxiliaryAudioURL else {
                            throw CocoaError(.fileNoSuchFile)
                        }
                        try await m4a2mp3(inputUrl: auxiliaryAudioURL, outputUrl: outputURL, bitrateKbps: audioQuality.rawValue)
                        try fd.removeItem(at: auxiliaryAudioURL)
                        finalize(.success(RecordingArtifact(kind: .audio, production: .mp3Conversion, url: outputURL)))
                    } catch {
                        finalize(.failure(RecordingFailure(stage: .mp3Conversion, message: error.localizedDescription, retainedURL: auxiliaryAudioURL)))
                    }
                }
            } else if remuxesAudio && recordsMicrophone {
                Task {
                    do {
                        let document = try qmaPackageHandle.load(from: primaryURL)
                        let audioPlayerManager = AudioPlayerManager()
                        try audioPlayerManager.loadAudioFiles(format: document.info.format, package: primaryURL, encoder: document.info.encoder, saveMP3: document.info.exportMP3)
                        audioPlayerManager.sysVol = document.info.sysVol
                        audioPlayerManager.micVol = document.info.micVol
                        let exportMP3 = document.info.exportMP3
                        let format = exportMP3 ? "mp3" : document.info.format
                        let saveURL = primaryURL.deletingPathExtension().appendingPathExtension(format)
                        let outputURL = try await audioPlayerManager.exportFile(saveURL, saveAsMP3: exportMP3)
                        finalize(.success(RecordingArtifact(kind: .audio, production: .qmaExport, url: outputURL)))
                    } catch {
                        let stage: RecordingFailure.Stage = (try? qmaPackageHandle.load(from: primaryURL)) == nil ? .qmaLoad : .qmaExport
                        finalize(.failure(RecordingFailure(stage: stage, message: error.localizedDescription, retainedURL: primaryURL)))
                    }
                }
            } else {
                let production: RecordingArtifact.Production = recordsMicrophone ? .qmaPackage : .systemAudioWriter
                let kind: RecordingArtifact.Kind = recordsMicrophone ? .package : .audio
                finalize(.success(RecordingArtifact(kind: kind, production: production, url: primaryURL)))
            }
        } else if recordsMicrophone && recordsSystemAudio && remuxesAudio {
            Task {
                do {
                    let outputURL = try await mixAudioTracks(
                        videoURL: primaryURL,
                        fileExtension: settings.videoFormat.rawValue
                    )
                    finalize(.success(RecordingArtifact(kind: .video, production: .audioRemix, url: outputURL)))
                } catch {
                    finalize(.failure(RecordingFailure(stage: .audioRemix, message: error.localizedDescription, retainedURL: primaryURL)))
                }
            }
        } else {
            finalize(.success(RecordingArtifact(kind: .video, production: .screenCaptureWriter, url: primaryURL)))
        }
        
        isPaused = false
        hideMousePointer = false
        window = nil
        screen = nil
        startTime = nil
        AppDelegate.shared.presenterType = "OFF"
        updateStatusBar()
        
            streamType = nil
        }
    }

    static func completeFinalization(_ outcome: FinalizationOutcome) {
        partialQMAPackagePath = nil
        _ = AppDelegate.shared.recordingSession.finish(outcome) { request, outcome in
            let policy = RecordingCompletionPolicy.evaluate(
                outcome: outcome,
                showsPreview: request.settings.showsPreview,
                trimsAfterRecording: request.settings.trimsAfterRecording
            )
            switch outcome {
            case let .success(artifact):
                if policy.dispatchesArchive { handleCompletedVideo(url: artifact.url) }
                if policy.sendsNotification {
                    showNotification(
                        title: "Recording Completed".local,
                        body: String(format: "File saved to: %@".local, artifact.url.path),
                        id: "quickrecorder.completed.\(UUID().uuidString)"
                    )
                }
                if policy.offersTrim {
                    AppDelegate.shared.createNewWindow(
                        view: VideoTrimmerView(videoURL: artifact.url),
                        title: artifact.url.lastPathComponent,
                        only: false
                    )
                } else if policy.presentsPreview {
                    let image: NSImage?
                    switch artifact.kind {
                    case .video: image = nil
                    case .audio: image = NSImage(named: "audioIcon")
                    case .package: image = NSImage(named: "qmaIcon")
                    }
                    showPreview(path: artifact.url.path, image: image, enabled: true)
                }
            case let .failure(failure):
                showNotification(
                    title: "Failed to save file".local,
                    body: failure.message,
                    id: "quickrecorder.error.\(UUID().uuidString)"
                )
            }
            firstFrame = nil
        }
    }

    static func handleCompletedVideo(url: URL) {
        guard ["mp4", "mov"].contains(url.pathExtension.lowercased()) else { return }
        ArchiveCompressionService.shared.recordingDidComplete(url: url)
    }
    
    static func showPreview(path: String, image: NSImage? = nil, enabled: Bool? = nil) {
        if !(enabled ?? ud.bool(forKey: "showPreview")) { return }
        var previewImage: NSImage?
        let previewURL = fd.temporaryDirectory.appendingPathComponent("qr-preview.jpg")
        if image == nil { firstFrame?.nsImage?.saveToFile(previewURL, type: .jpeg) }
        
        if let i = image { previewImage = i } else { previewImage = NSImage(contentsOf: previewURL) }
        if let previewImage = previewImage, let screen = getScreenWithMouse() {
            let contentView = NSHostingView(rootView: PreviewView(frame: previewImage, filePath: path))
            previewWindow.contentView = contentView
            previewWindow.setFrameOrigin(NSPoint(x: screen.frame.maxX - 280, y: screen.frame.minY + 20))
            previewWindow.orderFront(self)
        }
    }
    
    static func m4a2mp3(inputUrl: URL, outputUrl: URL, bitrateKbps: Int? = nil) async throws {
        let progress = Progress()
        let lameEncoder = try SwiftLameEncoder(
            sourceUrl: inputUrl,
            configuration: .init(
                sampleRate: .custom(48000),
                bitrateMode: .constant(Int32(bitrateKbps ?? ud.integer(forKey: "audioQuality"))),
                quality: .nearBest
            ),
            destinationUrl: outputUrl,
            progress: progress // optional
        )
        try await lameEncoder.encode(priority: .userInitiated)
    }
    
    static func trimVideo(enabled: Bool? = nil) {
        if enabled ?? ud.bool(forKey: "trimAfterRecord") {
            let fileURL = filePath.url
            AppDelegate.shared.createNewWindow(view: VideoTrimmerView(videoURL: fileURL), title: fileURL.lastPathComponent, only: false)
        }
    }
    
    static func getCameras() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .externalUnknown], mediaType: .video, position: .unspecified)
        return discoverySession.devices
    }
    
    static func getMicrophone() -> [AVCaptureDevice] {
        var discoverySession: AVCaptureDevice.DiscoverySession
        if #available(macOS 15.0, *) {
            discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInMicrophone, .microphone], mediaType: .audio, position: .unspecified)
        } else {
            discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInMicrophone, .externalUnknown], mediaType: .audio, position: .unspecified)
        }
        return discoverySession.devices.filter({ !$0.localizedName.contains("CADefaultDeviceAggregate") })
    }
    
    static func getiDevice() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.externalUnknown], mediaType: .muxed, position: .unspecified)
        return discoverySession.devices
    }
    
    static func getCurrentMic() -> AVCaptureDevice? {
        let deviceName = AppDelegate.shared.recordingSession.request?.settings.microphoneDevice
            ?? ud.string(forKey: "micDevice")
        return getMicrophone().first(where: { $0.localizedName == deviceName })
    }
    
    /*static func getChannelCount() -> Int? {
        if let device = getCurrentMic() {
            if let channels = device.formats.first?.formatDescription.audioChannelLayout?.numberOfChannels {
                return channels
            }
            
            let activeFormat = device.activeFormat
            let description = activeFormat.formatDescription
            if let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                let channelCount = audioStreamBasicDescription.mChannelsPerFrame
                return max(2, Int(channelCount))
            }
        }
        return getDefaultChannelCount()
    }
    
    static func getDefaultChannelCount() -> Int? {
        var deviceID = AudioObjectID(0)
        var propertySize = UInt32(MemoryLayout.size(ofValue: deviceID))
        
        // 获取默认音频输入设备
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        
        guard status == noErr else {
            print("Failed to get default audio input device")
            return nil
        }
        
        // 获取通道数
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // 查询流配置信息
        var streamConfig: UnsafeMutableAudioBufferListPointer?
        propertySize = 0
        
        // 先获取属性大小
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize)
        guard sizeStatus == noErr else {
            print("Failed to get size for stream configuration")
            return nil
        }
        
        // 分配内存以存储音频流配置
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propertySize))
        defer { bufferList.deallocate() }
        
        let configStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, bufferList)
        guard configStatus == noErr else {
            print("Failed to get stream configuration")
            return nil
        }
        
        streamConfig = UnsafeMutableAudioBufferListPointer(bufferList)
        
        // 计算通道总数
        var totalChannels = 0
        for buffer in streamConfig! {
            totalChannels += Int(buffer.mNumberChannels)
        }
        return max(2, totalChannels)
    }*/
    
    static func getSampleRate() -> Int? {
        if let device = getCurrentMic() {
            let activeFormat = device.activeFormat
            let description = activeFormat.formatDescription
            
            if let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                let sampleRate = audioStreamBasicDescription.mSampleRate
                return Int(sampleRate)
            }
        }
        return getDefaultSampleRate()
    }
    
    static func getDefaultSampleRate() -> Int? {
        var deviceID = AudioObjectID(0)
        var propertySize = UInt32(MemoryLayout.size(ofValue: deviceID))
        
        // 获取默认音频输入设备
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        
        guard status == noErr else {
            print("Failed to get default audio input device")
            return nil
        }
        
        // 获取采样率
        var sampleRate: Double = 0
        propertySize = UInt32(MemoryLayout.size(ofValue: sampleRate))
        
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let sampleRateStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &sampleRate
        )
        
        guard sampleRateStatus == noErr else {
            print("Failed to get sample rate for the default input device")
            return nil
        }
        
        return Int(sampleRate)
    }
    
    static func adjustTime(sample: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        guard CMSampleBufferGetFormatDescription(sample) != nil else { return nil }
        
        var timingInfo = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: Int(CMSampleBufferGetNumSamples(sample)))
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: timingInfo.count, arrayToFill: &timingInfo, entriesNeededOut: nil)
        
        for i in 0..<timingInfo.count {
            timingInfo[i].decodeTimeStamp = CMTimeSubtract(timingInfo[i].decodeTimeStamp, offset)
            timingInfo[i].presentationTimeStamp = CMTimeSubtract(timingInfo[i].presentationTimeStamp, offset)
        }
        
        var outSampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: timingInfo.count, sampleTimingArray: &timingInfo, sampleBufferOut: &outSampleBuffer)
        
        return outSampleBuffer
    }
    
    static func showNotification(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Notification failed to send：\(error.localizedDescription)") }
        }
    }

    static func mixedRecordingSourcePath(basePath: String, fileExtension: String) -> String {
        "\(basePath).mixing-source.\(fileExtension)"
    }

    private static func mixedRecordingOutputURLs(videoURL: URL, fileExtension: String) -> (audioURL: URL, finalURL: URL) {
        let sourceStem = videoURL.deletingPathExtension()
        if sourceStem.pathExtension.lowercased() == "mixing-source" {
            let baseURL = sourceStem.deletingPathExtension()
            return (
                baseURL.appendingPathExtension("mixed-audio").appendingPathExtension(fileExtension),
                baseURL.appendingPathExtension(fileExtension)
            )
        }

        if sourceStem.pathExtension.lowercased() == fileExtension.lowercased() {
            return (sourceStem, sourceStem.deletingPathExtension())
        }

        return (
            sourceStem.appendingPathExtension("mixed-audio").appendingPathExtension(fileExtension),
            sourceStem.appendingPathExtension(fileExtension)
        )
    }
    
    static func mixAudioTracks(videoURL: URL, fileExtension: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            mixAudioTracks(videoURL: videoURL, fileExtension: fileExtension) { result in
                continuation.resume(with: result)
            }
        }
    }

    private static func mixAudioTracks(videoURL: URL, fileExtension: String, completion: @escaping (Result<URL, Error>) -> Void) {
        showNotification(title: "Still Processing".local, body: "Mixing audio track...".local, id: "quickrecorder.processing.\(UUID().uuidString)")
        
        let asset = AVAsset(url: videoURL)
        let audioOnlyComposition = AVMutableComposition()
        
        let fileEnding = fileExtension
        var fileType: AVFileType?
        switch fileEnding {
        case VideoFormat.mov.rawValue: fileType = AVFileType.mov
        case VideoFormat.mp4.rawValue: fileType = AVFileType.mp4
        default: assertionFailure("loaded unknown video format".local)
        }

        let outputURLs = mixedRecordingOutputURLs(videoURL: videoURL, fileExtension: fileEnding)
        let audioOutputURL = outputURLs.audioURL
        let outputURL = outputURLs.finalURL
        
        let audioTracks = asset.tracks(withMediaType: .audio)
        guard audioTracks.count > 1 else {
            completion(.failure(NSError(domain: "AudioTrackError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not enough audio tracks found."])))
            return
        }
        
        for audioTrack in audioTracks {
            if let compositionAudioTrack = audioOnlyComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                do {
                    try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: audioTrack, at: .zero)
                } catch {
                    completion(.failure(NSError(domain: "AudioTrackInsertionError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to insert audio track: \(error.localizedDescription)"])))
                    return
                }
            }
        }
        
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioTracks.map {
            let parameters = AVMutableAudioMixInputParameters(track: $0)
            parameters.trackID = $0.trackID
            return parameters
        }
        
        guard let audioExportSession = AVAssetExportSession(asset: audioOnlyComposition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(.failure(NSError(domain: "AudioExportSessionError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio export session."])))
            return
        }
        audioExportSession.outputURL = audioOutputURL
        audioExportSession.outputFileType = fileType ?? .mp4
        audioExportSession.audioMix = audioMix
        
        audioExportSession.exportAsynchronously {
            /*var exportStatus: AVAssetExportSession.Status = .unknown
            
            // Loop until export session is completed, failed, or cancelled
            while exportStatus != .completed && exportStatus != .failed && exportStatus != .cancelled {
                exportStatus = audioExportSession.status
                Thread.sleep(forTimeInterval: 0.1)
            }*/
            
            switch audioExportSession.status {
            case .completed:
                let audioAsset = AVAsset(url: audioOutputURL)
                let composition = AVMutableComposition()
                
                guard let videoTrack = asset.tracks(withMediaType: .video).first,
                      let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    completion(.failure(NSError(domain: "VideoTrackError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get video track."])))
                    return
                }
                
                do {
                    try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
                } catch {
                    completion(.failure(NSError(domain: "VideoTrackInsertionError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to insert video track: \(error.localizedDescription)"])))
                    return
                }
                
                let audioTracks = audioAsset.tracks(withMediaType: .audio)
                guard audioTracks.count >= 1 else {
                    completion(.failure(NSError(domain: "AudioTrackError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not enough audio tracks found."])))
                    return
                }
                
                for audioTrack in audioTracks {
                    if let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                        do {
                            try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: audioTrack, at: .zero)
                        } catch {
                            completion(.failure(NSError(domain: "AudioTrackInsertionError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to insert audio track: \(error.localizedDescription)"])))
                            return
                        }
                    }
                }
                
                guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                    completion(.failure(NSError(domain: "ExportSessionError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session."])))
                    return
                }
                
                exportSession.outputURL = outputURL
                exportSession.outputFileType = fileType ?? .mp4
                exportSession.audioMix = audioMix
                
                exportSession.exportAsynchronously {
                    switch exportSession.status {
                    case .completed:
                        let  fileManager = fd
                        try? fileManager.removeItem(atPath: videoURL.path)
                        try? fileManager.removeItem(atPath: audioOutputURL.path)
                        completion(.success(outputURL))
                    case .failed:
                        completion(.failure(exportSession.error ?? NSError(domain: "ExportError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export failed for an unknown reason."])))
                    case .cancelled:
                        completion(.failure(NSError(domain: "ExportCancelled", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export was cancelled."])))
                    default:
                        completion(.failure(NSError(domain: "ExportStateError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video export ended in an unexpected state."])))
                    }
                }
            case .failed:
                completion(.failure(audioExportSession.error ?? NSError(domain: "ExportError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export failed for an unknown reason."])))
            case .cancelled:
                completion(.failure(NSError(domain: "ExportCancelled", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export was cancelled."])))
            default:
                completion(.failure(NSError(domain: "ExportStateError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio export ended in an unexpected state."])))
            }
        }
    }
}
