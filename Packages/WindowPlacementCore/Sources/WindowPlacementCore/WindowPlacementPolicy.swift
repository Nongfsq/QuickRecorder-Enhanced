import CoreGraphics

public struct WindowPlacementPolicy: Sendable {
    public var minimumReachableWidth: CGFloat
    public var minimumReachableTitlebarHeight: CGFloat

    public init(
        minimumReachableWidth: CGFloat = 96,
        minimumReachableTitlebarHeight: CGFloat = 32
    ) {
        self.minimumReachableWidth = minimumReachableWidth
        self.minimumReachableTitlebarHeight = minimumReachableTitlebarHeight
    }

    public func recoveredFrame(
        _ windowFrame: CGRect,
        visibleFrames: [CGRect],
        preferredVisibleFrame: CGRect? = nil
    ) -> CGRect {
        guard !visibleFrames.isEmpty else { return windowFrame }
        if isMeaningfullyReachable(windowFrame, onAny: visibleFrames) {
            return windowFrame
        }

        let intersectingFrame = visibleFrames.max {
            intersectionArea(windowFrame, $0) < intersectionArea(windowFrame, $1)
        }
        let hasIntersection = intersectingFrame.map { intersectionArea(windowFrame, $0) > 0 } ?? false
        let target = hasIntersection
            ? intersectingFrame!
            : resolvedPreferredFrame(preferredVisibleFrame, visibleFrames: visibleFrames)
        let fittedSize = fittedSize(windowFrame.size, inside: target.size)

        if hasIntersection {
            return CGRect(
                origin: clampedOrigin(windowFrame.origin, size: fittedSize, inside: target),
                size: fittedSize
            )
        }

        return centeredFrame(size: fittedSize, inside: target)
    }

    public func centeredFrame(
        size: CGSize,
        visibleFrames: [CGRect],
        preferredVisibleFrame: CGRect? = nil
    ) -> CGRect? {
        guard !visibleFrames.isEmpty else { return nil }
        let target = resolvedPreferredFrame(preferredVisibleFrame, visibleFrames: visibleFrames)
        return centeredFrame(size: fittedSize(size, inside: target.size), inside: target)
    }

    public func isMeaningfullyReachable(_ windowFrame: CGRect, onAny visibleFrames: [CGRect]) -> Bool {
        guard windowFrame.width > 0, windowFrame.height > 0 else { return false }
        let titlebarHeight = min(minimumReachableTitlebarHeight, windowFrame.height)
        let titlebar = CGRect(
            x: windowFrame.minX,
            y: windowFrame.maxY - titlebarHeight,
            width: windowFrame.width,
            height: titlebarHeight
        )
        let requiredWidth = min(minimumReachableWidth, windowFrame.width)

        return visibleFrames.contains { visibleFrame in
            let intersection = titlebar.intersection(visibleFrame)
            return !intersection.isNull
                && intersection.width >= requiredWidth
                && intersection.height >= titlebarHeight
        }
    }

    private func resolvedPreferredFrame(_ preferred: CGRect?, visibleFrames: [CGRect]) -> CGRect {
        guard let preferred else { return visibleFrames[0] }
        return visibleFrames.first(where: { approximatelyEqual($0, preferred) }) ?? visibleFrames[0]
    }

    private func fittedSize(_ size: CGSize, inside bounds: CGSize) -> CGSize {
        CGSize(width: min(max(1, size.width), bounds.width), height: min(max(1, size.height), bounds.height))
    }

    private func centeredFrame(size: CGSize, inside bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func clampedOrigin(_ origin: CGPoint, size: CGSize, inside bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, bounds.minX), bounds.maxX - size.width),
            y: min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        )
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.5
            && abs(lhs.minY - rhs.minY) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    }
}
