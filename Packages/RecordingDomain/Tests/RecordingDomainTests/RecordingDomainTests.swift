import XCTest
@testable import RecordingDomain

final class RecordingDomainTests: XCTestCase {
    func testHappyPathPreservesSessionIdentity() throws {
        let id = UUID()
        let startedAt = Date(timeIntervalSince1970: 100)
        var machine = RecordingSessionStateMachine()

        XCTAssertEqual(try machine.apply(.prepare(id: id)), .preparing(id: id))
        XCTAssertEqual(try machine.apply(.start(at: startedAt)), .recording(id: id, startedAt: startedAt))
        XCTAssertEqual(try machine.apply(.pause), .paused(id: id, startedAt: startedAt))
        XCTAssertEqual(try machine.apply(.resume), .recording(id: id, startedAt: startedAt))
        XCTAssertEqual(try machine.apply(.stop), .stopping(id: id))
        XCTAssertEqual(try machine.apply(.beginFinalizing), .finalizing(id: id))
        XCTAssertEqual(try machine.apply(.complete), .completed(id: id))
        XCTAssertEqual(try machine.apply(.reset), .idle)
    }

    func testInvalidTransitionDoesNotMutateState() {
        var machine = RecordingSessionStateMachine()

        XCTAssertThrowsError(try machine.apply(.pause)) { error in
            XCTAssertEqual(
                error as? InvalidRecordingTransition,
                InvalidRecordingTransition(state: .idle, event: .pause)
            )
        }
        XCTAssertEqual(machine.state, .idle)
    }

    func testFailureRetainsActiveSessionAndCanReset() throws {
        let id = UUID()
        var machine = RecordingSessionStateMachine()

        try machine.apply(.prepare(id: id))
        XCTAssertEqual(
            try machine.apply(.fail(reason: "capture unavailable")),
            .failed(id: id, reason: "capture unavailable")
        )
        XCTAssertEqual(try machine.apply(.reset), .idle)
    }

    func testStableRawValuesRemainCompatibleWithPreferences() {
        XCTAssertEqual(Encoder.h265.rawValue, "h265")
        XCTAssertEqual(VideoFormat.mp4.rawValue, "mp4")
        XCTAssertEqual(AudioQuality.high.rawValue, 256)
        XCTAssertEqual(StreamType.screenarea.rawValue, 4)
        XCTAssertEqual(PixFormat.delault.rawValue, "delault")
    }

    func testSnapshotNormalizesUnsafeOrUnsupportedPreferenceValues() {
        let snapshot = makeSnapshot(
            frameRate: 0,
            resolutionScale: 9,
            videoQuality: 0.62,
            recordHDR: true,
            withAlpha: true,
            enablesAEC: true,
            microphoneNoiseReduction: true,
            aecLevel: "unknown",
            background: .clear,
            presenterOverlaySafeDelay: -4
        )

        XCTAssertEqual(snapshot.frameRate, 1)
        XCTAssertEqual(snapshot.resolutionScale, 2)
        XCTAssertEqual(snapshot.videoQuality, 0.7)
        XCTAssertFalse(snapshot.withAlpha)
        XCTAssertFalse(snapshot.enablesAEC)
        XCTAssertEqual(snapshot.aecLevel, "mid")
        XCTAssertEqual(snapshot.background, .wallpaper)
        XCTAssertEqual(snapshot.presenterOverlaySafeDelay, 0)
    }

    func testLegacyEntryRoutesCreateEquivalentTypedModes() {
        XCTAssertEqual(StreamType(legacyCaptureType: "display"), .screen)
        XCTAssertEqual(StreamType(legacyCaptureType: "window"), .window)
        XCTAssertEqual(StreamType(legacyCaptureType: "windows"), .windows)
        XCTAssertEqual(StreamType(legacyCaptureType: "application"), .application)
        XCTAssertEqual(StreamType(legacyCaptureType: "area"), .screenarea)
        XCTAssertEqual(StreamType(legacyCaptureType: "audio"), .systemaudio)
        XCTAssertNil(StreamType(legacyCaptureType: "camera"))
    }

    func testRequestFreezesSettingsByValue() {
        var settings = makeSnapshot(frameRate: 15)
        let request = RecordingRequest(mode: .screen, settings: settings, fastStart: false)

        settings.frameRate = 60

        XCTAssertEqual(request.settings.frameRate, 15)
        XCTAssertEqual(settings.frameRate, 60)
    }

    func testVideoEncodingPolicyPreservesAutomaticAndConfiguredBitrateContracts() {
        let automatic = VideoEncodingPolicy.evaluate(
            .init(
                width: 1920,
                height: 1080,
                frameRate: 15,
                encoder: .h265,
                recordsHDR: false,
                quality: 1,
                configuredBitrateKbps: 0,
                adaptiveVFR: true
            )
        )
        let configured = VideoEncodingPolicy.evaluate(
            .init(
                width: 1920,
                height: 1080,
                frameRate: 15,
                encoder: .h265,
                recordsHDR: false,
                quality: 1,
                configuredBitrateKbps: 500,
                adaptiveVFR: false
            )
        )

        XCTAssertGreaterThanOrEqual(automatic.averageBitrate, 200_000)
        XCTAssertEqual(automatic.maxKeyFrameIntervalDuration, 18)
        XCTAssertEqual(configured.averageBitrate, 500_000)
        XCTAssertEqual(configured.maxKeyFrameIntervalDuration, 2)
    }

    func testAdaptiveVFRKeepsDirtyAndIdleFramesButSkipsRedundantFrames() {
        let base = AdaptiveVFRInput(
            enabled: true,
            recordsHDR: false,
            hasFirstFrame: true,
            previousVideoTime: 10,
            currentVideoTime: 10.2,
            dirtyArea: 0,
            frameRate: 15
        )

        XCTAssertTrue(AdaptiveVFRPolicy.shouldSkip(base))

        var dirty = base
        dirty.dirtyArea = 20
        XCTAssertFalse(AdaptiveVFRPolicy.shouldSkip(dirty))

        var idleKeepAlive = base
        idleKeepAlive.currentVideoTime = 15
        XCTAssertFalse(AdaptiveVFRPolicy.shouldSkip(idleKeepAlive))

        var hdr = base
        hdr.recordsHDR = true
        XCTAssertFalse(AdaptiveVFRPolicy.shouldSkip(hdr))
    }

    func testPauseTimelineRemovesPausedGapAndKeepsMonotonicTime() throws {
        var timeline = PauseTimeline()

        XCTAssertEqual(timeline.adjustedTime(for: 10), 10)
        XCTAssertEqual(timeline.adjustedTime(for: 11), 11)
        timeline.pause()
        XCTAssertNil(timeline.adjustedTime(for: 12))
        timeline.resume()
        XCTAssertEqual(try XCTUnwrap(timeline.adjustedTime(for: 16, minimumStep: 0.02)), 11.02, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(timeline.adjustedTime(for: 17, minimumStep: 0.02)), 12.02, accuracy: 0.000_001)
        XCTAssertEqual(timeline.accumulatedOffset, 4.98, accuracy: 0.000_001)
    }

    func testPauseTimelineRejectsOutOfOrderAndInvalidSamples() {
        var timeline = PauseTimeline()

        XCTAssertEqual(timeline.adjustedTime(for: 5), 5)
        XCTAssertNil(timeline.adjustedTime(for: 5))
        XCTAssertNil(timeline.adjustedTime(for: 4))
        XCTAssertNil(timeline.adjustedTime(for: .infinity))
        XCTAssertEqual(timeline.lastEmittedTime, 5)
    }

    func testPauseTimelineResumeStepCanRepresentALowTimescaleTick() throws {
        var timeline = PauseTimeline()

        XCTAssertEqual(timeline.adjustedTime(for: 2), 2)
        timeline.pause()
        timeline.resume()
        XCTAssertEqual(
            try XCTUnwrap(timeline.adjustedTime(for: 8, minimumStep: 0.1)),
            2.1,
            accuracy: 0.000_001
        )
    }

    func testUserDefaultsSuiteFixtureProducesFrozenSnapshotForScreenAndIDevice() throws {
        let suiteName = "RecordingDomainTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("/tmp/fixture", forKey: "saveDirectory")
        defaults.set(30, forKey: "frameRate")
        defaults.set(1, forKey: "highRes")
        defaults.set(0.7, forKey: "videoQuality")
        defaults.set(VideoBitrate.kbps800.rawValue, forKey: "videoBitrate")
        defaults.set(VideoFormat.mov.rawValue, forKey: "videoFormat")
        defaults.set(Encoder.h265.rawValue, forKey: "encoder")
        defaults.set(true, forKey: "recordMic")
        defaults.set(false, forKey: "recordWinSound")
        defaults.set("Fixture Mic", forKey: "micDevice")
        defaults.set(true, forKey: "showPreview")

        let adapter = RecordingSettingsDefaultsAdapter(defaults: defaults)
        let screen = try XCTUnwrap(adapter.makeRequest(mode: .screen))
        let device = try XCTUnwrap(adapter.makeRequest(mode: .idevice))

        XCTAssertEqual(screen.settings, device.settings)
        XCTAssertEqual(device.mode, .idevice)
        XCTAssertEqual(device.settings.outputDirectory, "/tmp/fixture")
        XCTAssertEqual(device.settings.frameRate, 30)
        XCTAssertEqual(device.settings.resolutionScale, 1)
        XCTAssertEqual(device.settings.videoFormat, .mov)
        XCTAssertEqual(device.settings.encoder, .h265)
        XCTAssertTrue(device.settings.recordsMicrophone)
        XCTAssertFalse(device.settings.recordsSystemAudio)
        XCTAssertEqual(device.settings.microphoneDevice, "Fixture Mic")
    }

    func testTypedAndLegacyEntryAdaptersFreezeEquivalentRequests() throws {
        let suiteName = "RecordingDomainTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("/tmp/fixture", forKey: "saveDirectory")
        defaults.set(60, forKey: "frameRate")
        defaults.set(2, forKey: "highRes")

        let adapter = RecordingSettingsDefaultsAdapter(defaults: defaults)
        for legacy in ["display", "window", "windows", "application", "area", "audio"] {
            let mode = try XCTUnwrap(StreamType(legacyCaptureType: legacy))
            let typed = try XCTUnwrap(adapter.makeRequest(mode: mode, fastStart: true))
            let adapted = try XCTUnwrap(adapter.makeRequest(legacyCaptureType: legacy, fastStart: true))
            XCTAssertEqual(typed.mode, adapted.mode, legacy)
            XCTAssertEqual(typed.settings, adapted.settings, legacy)
            XCTAssertEqual(typed.fastStart, adapted.fastStart, legacy)
        }
    }

    func testCaptureDimensionPolicyCoversModernLegacyAreaAndAudio() {
        XCTAssertEqual(
            CaptureDimensionPolicy.evaluate(
                .init(
                    mode: .screen,
                    modernFilterSize: .init(width: 1512, height: 982),
                    pointPixelScale: 2,
                    resolutionScale: 2
                )
            ),
            CaptureDimensions(width: 3024, height: 1964)
        )
        XCTAssertEqual(
            CaptureDimensionPolicy.evaluate(
                .init(
                    mode: .window,
                    legacyDisplaySize: .init(width: 1920, height: 1080),
                    legacyWindowSize: .init(width: 640, height: 480),
                    pointPixelScale: 2,
                    resolutionScale: 1
                )
            ),
            CaptureDimensions(width: 640, height: 480)
        )
        XCTAssertEqual(
            CaptureDimensionPolicy.evaluate(
                .init(
                    mode: .screenarea,
                    modernFilterSize: .init(width: 1920, height: 1080),
                    selectedAreaSize: .init(width: 400, height: 300),
                    pointPixelScale: 2,
                    resolutionScale: 2
                )
            ),
            CaptureDimensions(width: 800, height: 600)
        )
        XCTAssertEqual(
            CaptureDimensionPolicy.evaluate(
                .init(mode: .systemaudio, pointPixelScale: 2, resolutionScale: 2)
            ),
            CaptureDimensions(width: 2, height: 2)
        )
    }

    func testAudioRenderDurationPolicyUsesLongestTrackAcrossSampleRates() {
        XCTAssertEqual(
            AudioRenderDurationPolicy.targetFrameCount(
                tracks: [
                    .init(frameCount: 44_100, sampleRate: 44_100),
                    .init(frameCount: 96_001, sampleRate: 48_000)
                ],
                outputSampleRate: 48_000
            ),
            96_001
        )
        XCTAssertEqual(
            AudioRenderDurationPolicy.targetFrameCount(
                tracks: [.init(frameCount: 44_101, sampleRate: 44_100)],
                outputSampleRate: 48_000
            ),
            48_002
        )
    }

    func testAudioRenderDurationPolicyRejectsInvalidRates() {
        XCTAssertNil(
            AudioRenderDurationPolicy.targetFrameCount(
                tracks: [.init(frameCount: 100, sampleRate: 0)],
                outputSampleRate: 48_000
            )
        )
        XCTAssertNil(
            AudioRenderDurationPolicy.targetFrameCount(
                tracks: [.init(frameCount: 100, sampleRate: 44_100)],
                outputSampleRate: .infinity
            )
        )
    }

    func testSuccessfulBackendMatrixHasArtifactParity() {
        let url = URL(fileURLWithPath: "/tmp/recording")
        let matrix: [(RecordingArtifact.Production, RecordingArtifact.Kind)] = [
            (.screenCaptureWriter, .video),
            (.audioRemix, .video),
            (.systemAudioWriter, .audio),
            (.mp3Conversion, .audio),
            (.qmaPackage, .package),
            (.qmaExport, .audio),
            (.deviceCapture, .video)
        ]

        for (production, kind) in matrix {
            let outcome = FinalizationOutcome.success(
                RecordingArtifact(kind: kind, production: production, url: url)
            )
            let policy = RecordingCompletionPolicy.evaluate(
                outcome: outcome,
                showsPreview: true,
                trimsAfterRecording: true
            )

            XCTAssertTrue(policy.presentsPreview, "\(production)")
            XCTAssertFalse(policy.sendsNotification, "\(production)")
            XCTAssertEqual(policy.offersTrim, kind == .video, "\(production)")
            XCTAssertEqual(policy.dispatchesArchive, kind == .video, "\(production)")
        }
    }

    func testFailureMatrixAlwaysNotifiesAndRetainsRecoveryLocation() {
        let retainedURL = URL(fileURLWithPath: "/tmp/source")
        let stages: [RecordingFailure.Stage] = [
            .writer, .audioRemix, .mp3Conversion, .qmaLoad, .qmaExport, .deviceCapture
        ]

        for stage in stages {
            let failure = RecordingFailure(stage: stage, message: "failed", retainedURL: retainedURL)
            let policy = RecordingCompletionPolicy.evaluate(
                outcome: .failure(failure),
                showsPreview: true,
                trimsAfterRecording: true
            )

            XCTAssertEqual(failure.retainedURL, retainedURL, "\(stage)")
            XCTAssertFalse(policy.presentsPreview, "\(stage)")
            XCTAssertTrue(policy.sendsNotification, "\(stage)")
            XCTAssertFalse(policy.offersTrim, "\(stage)")
            XCTAssertFalse(policy.dispatchesArchive, "\(stage)")
        }
    }

    func testSuccessWithoutPreviewUsesNotificationAndOnlyVideoGetsArchive() {
        let audio = FinalizationOutcome.success(
            RecordingArtifact(
                kind: .audio,
                production: .mp3Conversion,
                url: URL(fileURLWithPath: "/tmp/recording.mp3")
            )
        )
        let policy = RecordingCompletionPolicy.evaluate(
            outcome: audio,
            showsPreview: false,
            trimsAfterRecording: true
        )

        XCTAssertFalse(policy.presentsPreview)
        XCTAssertTrue(policy.sendsNotification)
        XCTAssertFalse(policy.offersTrim)
        XCTAssertFalse(policy.dispatchesArchive)
    }

    private func makeSnapshot(
        frameRate: Int = 60,
        resolutionScale: Int = 2,
        videoQuality: Double = 1.0,
        recordHDR: Bool = false,
        withAlpha: Bool = false,
        enablesAEC: Bool = false,
        microphoneNoiseReduction: Bool = false,
        aecLevel: String = "mid",
        background: BackgroundType = .wallpaper,
        presenterOverlaySafeDelay: Int = 1
    ) -> RecordingSettingsSnapshot {
        RecordingSettingsSnapshot(
            outputDirectory: "/tmp",
            frameRate: frameRate,
            resolutionScale: resolutionScale,
            videoQuality: videoQuality,
            videoBitrate: .auto,
            adaptiveVFR: false,
            videoFormat: .mp4,
            pixelFormat: .delault,
            encoder: .h265,
            recordHDR: recordHDR,
            withAlpha: withAlpha,
            audioFormat: .aac,
            audioQuality: .high,
            audioChannels: .stereo,
            recordsMicrophone: true,
            recordsSystemAudio: true,
            remuxesAudio: true,
            microphoneDevice: "default",
            enablesAEC: enablesAEC,
            microphoneNoiseReduction: microphoneNoiseReduction,
            aecLevel: aecLevel,
            background: background,
            showsMouse: true,
            highlightsMouse: false,
            includesMenuBar: true,
            hidesDesktopFiles: false,
            hidesSelf: true,
            hidesControlCenter: false,
            preventsSleep: true,
            showsPreview: true,
            trimsAfterRecording: false,
            presenterOverlaySafeDelay: presenterOverlaySafeDelay
        )
    }
}
