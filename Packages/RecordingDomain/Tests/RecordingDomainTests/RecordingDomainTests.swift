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

    func testPauseTimelineRemovesPausedGapAndKeepsMonotonicTime() {
        var timeline = PauseTimeline()

        XCTAssertEqual(timeline.adjustedTime(for: 10), 10)
        XCTAssertEqual(timeline.adjustedTime(for: 11), 11)
        timeline.pause()
        XCTAssertNil(timeline.adjustedTime(for: 12))
        timeline.resume()
        XCTAssertEqual(timeline.adjustedTime(for: 16), 11)
        XCTAssertEqual(timeline.adjustedTime(for: 17), 12)
        XCTAssertEqual(timeline.accumulatedOffset, 5)
    }

    func testPauseTimelineRejectsOutOfOrderAndInvalidSamples() {
        var timeline = PauseTimeline()

        XCTAssertEqual(timeline.adjustedTime(for: 5), 5)
        XCTAssertNil(timeline.adjustedTime(for: 4))
        XCTAssertNil(timeline.adjustedTime(for: .infinity))
        XCTAssertEqual(timeline.lastEmittedTime, 5)
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
