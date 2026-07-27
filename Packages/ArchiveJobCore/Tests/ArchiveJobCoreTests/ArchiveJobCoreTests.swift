import XCTest
@testable import ArchiveJobCore

final class ArchiveJobCoreTests: XCTestCase {
    func testStateOnlyRecoveryClassificationMatchesManifestClassification() {
        let manifest = makeManifest(status: .interrupted)
        let fromManifest = ArchiveRecoveryClassifier.classify(
            manifest: manifest,
            sourceExists: true,
            outputExists: false,
            temporaryOutputExists: true
        )
        let fromState = ArchiveRecoveryClassifier.classify(
            status: .interrupted,
            sourceExists: true,
            outputExists: false,
            temporaryOutputExists: true
        )
        XCTAssertEqual(fromState, fromManifest)
    }

    func testLegacyManifestDecodes() throws {
        let json = """
        {
          "id": "93434966-6D97-47AC-BE05-848975776517",
          "source": "/tmp/source.mp4",
          "output": "/tmp/output.mp4",
          "tempOutput": "/tmp/jobs/93434966-6D97-47AC-BE05-848975776517/encoded-av1.mp4",
          "status": "preparing",
          "detail": "Preparing AV1 archive",
          "crf": 56,
          "svtPreset": 8,
          "gop": 270,
          "audioMode": "aac-mono-64k",
          "startedAt": "2026-07-27T04:19:05Z"
        }
        """
        let manifest = try ArchiveManifestCodec.decode(Data(json.utf8))
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.status, .preparing)
        XCTAssertEqual(manifest.updatedAt, manifest.startedAt)
    }

    func testFutureSchemaIsRejected() {
        let json = """
        {
          "schemaVersion": 999,
          "id": "93434966-6D97-47AC-BE05-848975776517",
          "source": "/tmp/source.mp4",
          "output": "/tmp/output.mp4",
          "tempOutput": "/tmp/temp.mp4",
          "status": "preparing",
          "detail": "Preparing",
          "crf": 56,
          "svtPreset": 8,
          "gop": 270,
          "audioMode": "aac-mono-64k",
          "startedAt": "2026-07-27T04:19:05Z"
        }
        """
        XCTAssertThrowsError(try ArchiveManifestCodec.decode(Data(json.utf8)))
    }

    func testVersionTwoRoundTripPreservesRecoveryFields() throws {
        var manifest = makeManifest(status: .interrupted)
        manifest.progress = 0.42
        manifest.error = "interrupted"
        manifest.validation = ["status": .string("pass"), "frameCount": .number(120)]
        let decoded = try ArchiveManifestCodec.decode(ArchiveManifestCodec.encode(manifest))
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.id, manifest.id)
        XCTAssertEqual(decoded.progress, 0.42)
        XCTAssertEqual(decoded.validation, manifest.validation)
    }

    func testInterruptedTemporaryOutputIsValidatedBeforeRestart() {
        let manifest = makeManifest(status: .interrupted)
        XCTAssertEqual(
            ArchiveRecoveryClassifier.classify(
                manifest: manifest,
                sourceExists: true,
                outputExists: false,
                temporaryOutputExists: true
            ),
            .validateTemporaryOutput
        )
    }

    func testTaskOwnedPathRejectsSiblingDirectory() {
        let id = UUID()
        let root = URL(fileURLWithPath: "/tmp/ArchiveJobs", isDirectory: true)
        XCTAssertTrue(ArchivePathSafety.isTaskOwned(root.appendingPathComponent(id.uuidString).appendingPathComponent("encoded.mp4"), jobsRoot: root, jobID: id))
        XCTAssertFalse(ArchivePathSafety.isTaskOwned(root.appendingPathComponent("other/encoded.mp4"), jobsRoot: root, jobID: id))
    }

    func testCompletedManifestWithMissingOutputNeedsAttention() {
        let manifest = makeManifest(status: .completed)
        XCTAssertEqual(
            ArchiveRecoveryClassifier.classify(
                manifest: manifest,
                sourceExists: true,
                outputExists: false,
                temporaryOutputExists: false
            ),
            .completedOutputMissing
        )
    }

    private func makeManifest(status: ArchiveJobState) -> ArchiveJobManifest {
        ArchiveJobManifest(
            id: UUID(),
            source: "/tmp/source.mp4",
            output: "/tmp/output.mp4",
            tempOutput: "/tmp/temp.mp4",
            status: status,
            detail: status.rawValue,
            crf: 56,
            svtPreset: 8,
            gop: 270,
            audioMode: "aac-mono-64k",
            startedAt: Date()
        )
    }
}
