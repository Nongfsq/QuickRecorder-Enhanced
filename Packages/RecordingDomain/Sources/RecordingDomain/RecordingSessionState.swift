import Foundation

public enum RecordingSessionState: Equatable, Sendable {
    case idle
    case preparing(id: UUID)
    case recording(id: UUID, startedAt: Date)
    case paused(id: UUID, startedAt: Date)
    case stopping(id: UUID)
    case finalizing(id: UUID)
    case completed(id: UUID)
    case failed(id: UUID?, reason: String)

    public var sessionID: UUID? {
        switch self {
        case .idle:
            return nil
        case let .preparing(id), let .recording(id, _), let .paused(id, _),
             let .stopping(id), let .finalizing(id), let .completed(id):
            return id
        case let .failed(id, _):
            return id
        }
    }
}

public enum RecordingSessionEvent: Equatable, Sendable {
    case prepare(id: UUID)
    case start(at: Date)
    case pause
    case resume
    case stop
    case beginFinalizing
    case complete
    case fail(reason: String)
    case reset
}

public struct InvalidRecordingTransition: Error, Equatable, Sendable {
    public let state: RecordingSessionState
    public let event: RecordingSessionEvent

    public init(state: RecordingSessionState, event: RecordingSessionEvent) {
        self.state = state
        self.event = event
    }
}

public struct RecordingSessionStateMachine: Sendable {
    public private(set) var state: RecordingSessionState

    public init(state: RecordingSessionState = .idle) {
        self.state = state
    }

    @discardableResult
    public mutating func apply(_ event: RecordingSessionEvent) throws -> RecordingSessionState {
        let next: RecordingSessionState

        switch (state, event) {
        case (.idle, let .prepare(id)):
            next = .preparing(id: id)
        case (let .preparing(id), let .start(at)):
            next = .recording(id: id, startedAt: at)
        case (let .recording(id, startedAt), .pause):
            next = .paused(id: id, startedAt: startedAt)
        case (let .paused(id, startedAt), .resume):
            next = .recording(id: id, startedAt: startedAt)
        case (let .recording(id, _), .stop), (let .paused(id, _), .stop):
            next = .stopping(id: id)
        case (let .stopping(id), .beginFinalizing):
            next = .finalizing(id: id)
        case (let .finalizing(id), .complete):
            next = .completed(id: id)
        case (.completed, .reset), (.failed, .reset):
            next = .idle
        case (.idle, let .fail(reason)):
            next = .failed(id: nil, reason: reason)
        case (let current, let .fail(reason)) where current.sessionID != nil:
            next = .failed(id: current.sessionID, reason: reason)
        default:
            throw InvalidRecordingTransition(state: state, event: event)
        }

        state = next
        return next
    }
}
