import Foundation

public struct RecordingArtifact: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case video
        case audio
        case package
    }

    public enum Production: Equatable, Sendable {
        case screenCaptureWriter
        case audioRemix
        case systemAudioWriter
        case mp3Conversion
        case qmaPackage
        case qmaExport
        case deviceCapture
    }

    public let kind: Kind
    public let production: Production
    public let url: URL

    public init(kind: Kind, production: Production, url: URL) {
        self.kind = kind
        self.production = production
        self.url = url
    }
}

public struct RecordingFailure: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        case writer
        case audioRemix
        case mp3Conversion
        case qmaLoad
        case qmaExport
        case deviceCapture
    }

    public let stage: Stage
    public let message: String
    public let retainedURL: URL?

    public init(stage: Stage, message: String, retainedURL: URL?) {
        self.stage = stage
        self.message = message
        self.retainedURL = retainedURL
    }
}

public enum FinalizationOutcome: Equatable, Sendable {
    case success(RecordingArtifact)
    case failure(RecordingFailure)
}

public struct RecordingCompletionPolicy: Equatable, Sendable {
    public let presentsPreview: Bool
    public let sendsNotification: Bool
    public let offersTrim: Bool
    public let dispatchesArchive: Bool

    public init(
        presentsPreview: Bool,
        sendsNotification: Bool,
        offersTrim: Bool,
        dispatchesArchive: Bool
    ) {
        self.presentsPreview = presentsPreview
        self.sendsNotification = sendsNotification
        self.offersTrim = offersTrim
        self.dispatchesArchive = dispatchesArchive
    }

    public static func evaluate(
        outcome: FinalizationOutcome,
        showsPreview: Bool,
        trimsAfterRecording: Bool
    ) -> RecordingCompletionPolicy {
        switch outcome {
        case .failure:
            return RecordingCompletionPolicy(
                presentsPreview: false,
                sendsNotification: true,
                offersTrim: false,
                dispatchesArchive: false
            )
        case let .success(artifact):
            let isVideo = artifact.kind == .video
            return RecordingCompletionPolicy(
                presentsPreview: showsPreview,
                sendsNotification: !showsPreview,
                offersTrim: isVideo && trimsAfterRecording,
                dispatchesArchive: isVideo
            )
        }
    }
}
