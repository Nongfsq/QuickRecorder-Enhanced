import Foundation

final class RecordingSessionCoordinator {
    private let lock = NSLock()
    private var machine = RecordingSessionStateMachine()
    private var activeRequest: RecordingRequest?

    var request: RecordingRequest? {
        withLock { activeRequest }
    }

    var state: RecordingSessionState {
        withLock { machine.state }
    }

    @discardableResult
    func prepare(_ request: RecordingRequest) -> Bool {
        withLock {
            guard machine.state == .idle else { return false }
            do {
                try machine.apply(.prepare(id: request.id))
                activeRequest = request
                return true
            } catch {
                return false
            }
        }
    }

    func markStarted(at date: Date = Date()) {
        apply(.start(at: date))
    }

    func markPaused() {
        apply(.pause)
    }

    func markResumed() {
        apply(.resume)
    }

    func beginStopping() {
        apply(.stop)
    }

    func beginFinalizing() {
        apply(.beginFinalizing)
    }

    func complete() {
        apply(.complete)
        resetTerminalState()
    }

    func fail(_ reason: String) {
        apply(.fail(reason: reason))
        resetTerminalState()
    }

    private func apply(_ event: RecordingSessionEvent) {
        withLock {
            _ = try? machine.apply(event)
        }
    }

    private func resetTerminalState() {
        withLock {
            guard machine.state.sessionID != nil else { return }
            _ = try? machine.apply(.reset)
            activeRequest = nil
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
