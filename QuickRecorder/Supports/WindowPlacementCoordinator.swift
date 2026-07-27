import AppKit
import WindowPlacementCore

final class WindowPlacementCoordinator {
    enum WindowRole: String {
        case settings
        case mainPanel
        case content
        case document
        case cameraOverlay
        case deviceOverlay
        case recordingController
        case screenBound
        case transient

        var isRecoverable: Bool {
            switch self {
            case .settings, .mainPanel, .content, .document, .cameraOverlay, .deviceOverlay, .recordingController:
                return true
            case .screenBound, .transient:
                return false
            }
        }
    }

    static let shared = WindowPlacementCoordinator()

    private struct ManagedWindow {
        weak var window: NSWindow?
        let role: WindowRole
    }

    private let policy = WindowPlacementPolicy()
    private var managedWindows: [ObjectIdentifier: ManagedWindow] = [:]
    private var screenObserver: NSObjectProtocol?
    private var restorationObserver: NSObjectProtocol?
    private var windowBecameKeyObserver: NSObjectProtocol?

    private init() {}

    func start() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.recoverVisibleWindows()
            }
        }
        restorationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishRestoringWindowsNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.recoverVisibleWindows()
            }
        }
        windowBecameKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.recover(window)
        }

        register(camWindow, role: .cameraOverlay)
        register(deviceWindow, role: .deviceOverlay)
        register(controlPanel, role: .recordingController)
        register(countdownPanel, role: .screenBound)
        register(mousePointer, role: .transient)
        register(screenMagnifier, role: .transient)
        register(previewWindow, role: .transient)
    }

    func register(
        _ window: NSWindow,
        role: WindowRole,
        preferredScreen: NSScreen? = nil,
        recoverNow: Bool = true
    ) {
        managedWindows[ObjectIdentifier(window)] = ManagedWindow(window: window, role: role)
        if window.identifier == nil {
            window.identifier = NSUserInterfaceItemIdentifier("QuickRecorder.\(role.rawValue)")
        }
        if recoverNow, role.isRecoverable {
            recover(window, preferredScreen: preferredScreen)
        }
        pruneReleasedWindows()
    }

    func placeNew(
        _ window: NSWindow,
        role: WindowRole,
        preferredScreen: NSScreen?,
        offset: CGPoint = .zero
    ) {
        let screens = NSScreen.screens
        let visibleFrames = screens.map(\.visibleFrame)
        let preferred = preferredScreen?.visibleFrame
        if var frame = policy.centeredFrame(
            size: window.frame.size,
            visibleFrames: visibleFrames,
            preferredVisibleFrame: preferred
        ) {
            frame.origin.x += offset.x
            frame.origin.y += offset.y
            frame = policy.recoveredFrame(
                frame,
                visibleFrames: visibleFrames,
                preferredVisibleFrame: preferred
            )
            window.setFrame(frame, display: false)
        }
        register(window, role: role, preferredScreen: preferredScreen, recoverNow: false)
    }

    func recover(_ window: NSWindow, preferredScreen: NSScreen? = nil) {
        guard let managed = managedWindows[ObjectIdentifier(window)], managed.role.isRecoverable else { return }
        let screens = NSScreen.screens
        let recovered = policy.recoveredFrame(
            window.frame,
            visibleFrames: screens.map(\.visibleFrame),
            preferredVisibleFrame: preferredScreen?.visibleFrame
        )
        guard recovered != window.frame else { return }
        window.setFrame(recovered, display: true, animate: window.isVisible)
#if DEBUG
        print("Recovered \(managed.role.rawValue) window for \(screens.count) active screen(s).")
#endif
    }

    func recoverVisibleWindows() {
        pruneReleasedWindows()
        for managed in managedWindows.values where managed.role.isRecoverable {
            guard let window = managed.window, window.isVisible || window.isMiniaturized else { continue }
            recover(window)
        }
    }

    private func pruneReleasedWindows() {
        managedWindows = managedWindows.filter { $0.value.window != nil }
    }
}
