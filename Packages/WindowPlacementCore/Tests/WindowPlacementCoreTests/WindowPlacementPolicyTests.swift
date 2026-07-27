import CoreGraphics
import XCTest
@testable import WindowPlacementCore

final class WindowPlacementPolicyTests: XCTestCase {
    private let policy = WindowPlacementPolicy()
    private let primary = CGRect(x: 0, y: 25, width: 1440, height: 875)

    func testKeepsReachableWindowOnNegativeCoordinateDisplay() {
        let leftDisplay = CGRect(x: -1920, y: 0, width: 1920, height: 1050)
        let window = CGRect(x: -1500, y: 250, width: 900, height: 650)

        XCTAssertEqual(policy.recoveredFrame(window, visibleFrames: [primary, leftDisplay]), window)
    }

    func testCentersWindowOnPrimaryAfterExternalDisplayRemoval() {
        let stale = CGRect(x: 1800, y: 200, width: 900, height: 650)
        let recovered = policy.recoveredFrame(stale, visibleFrames: [primary])

        XCTAssertEqual(recovered, CGRect(x: 270, y: 137.5, width: 900, height: 650))
    }

    func testClampsPartiallyIntersectingWindowUntilTitlebarIsReachable() {
        let window = CGRect(x: 1380, y: 300, width: 500, height: 400)
        let recovered = policy.recoveredFrame(window, visibleFrames: [primary])

        XCTAssertEqual(recovered, CGRect(x: 940, y: 300, width: 500, height: 400))
    }

    func testFitsOversizedWindowInsideVisibleFrame() {
        let stale = CGRect(x: 2000, y: -500, width: 2000, height: 1200)

        XCTAssertEqual(policy.recoveredFrame(stale, visibleFrames: [primary]), primary)
    }

    func testUsesPreferredLiveDisplayForNewWindow() {
        let rightDisplay = CGRect(x: 1440, y: 0, width: 1920, height: 1050)
        let result = policy.centeredFrame(
            size: CGSize(width: 800, height: 500),
            visibleFrames: [primary, rightDisplay],
            preferredVisibleFrame: rightDisplay
        )

        XCTAssertEqual(result, CGRect(x: 2000, y: 275, width: 800, height: 500))
    }

    func testMissingDisplayTopologyLeavesExistingFrameUnchanged() {
        let window = CGRect(x: 120, y: 120, width: 800, height: 500)

        XCTAssertEqual(policy.recoveredFrame(window, visibleFrames: []), window)
        XCTAssertNil(policy.centeredFrame(size: window.size, visibleFrames: []))
    }
}
