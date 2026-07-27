# ADR-0005: Role-Aware Multi-Display Window Placement

Status: Accepted

Date: 2026-07-27

## Context

QuickRecorder mixes SwiftUI-owned Settings/document windows with AppKit-created panels, editors, archive windows, selectors, and recording overlays. macOS may restore a saved window frame whose display has since been removed. The application previously had no display-topology observer or shared reachability rule, so an ordinary window could open outside every attached display.

Recording overlays are different: their coordinates describe a selected capture display or target and must not be treated like ordinary utility windows.

## Decision

- Keep platform-independent geometry in the `WindowPlacementCore` package.
- Let an app-owned `WindowPlacementCoordinator` observe display changes and adapt `NSScreen.visibleFrame`/`NSWindow.frame` to that policy.
- Classify windows by role. Settings, main, content, document, camera/device, and recording-controller windows are recoverable. Capture-bound selectors/outlines and mouse/capture transients are excluded.
- Preserve every meaningfully reachable frame. Correct only an unreachable title/control region.
- Preserve existing system frame persistence; validate the realized window instead of deleting frame defaults.
- Use the primary screen as the deterministic recovery fallback and the pointer screen only as a preference for newly created ordinary windows.

## Consequences

- Display disconnect and rearrangement recovery is centralized and testable.
- A window intentionally positioned on a negative-coordinate display remains untouched while that display exists.
- New window families must declare a role rather than silently invent placement behavior.
- The coordinator is a bounded precursor to, not a replacement for, the typed route/window ownership planned in `ARCH-201`.

## Rejected Alternatives

- Clear all `NSWindow Frame` defaults: loses valid user placement and treats persistence as corrupt rather than stale.
- Call `center()` in each view: duplicates policy, misses live disconnects, and can choose the wrong screen.
- Recenter every window after every topology change: fights user intent and corrupts screen-bound capture geometry.
- Adopt a newer SwiftUI-only placement API: the app supports macOS 12.3 and owns important AppKit windows.

## Revisit Triggers

- `ARCH-201` supplies typed routes and stable window instances across the application.
- The deployment floor and SwiftUI APIs can fully control restored Settings, documents, AppKit panels, and live display removal.
- Product requirements add simultaneous capture sessions or new persistent screen-bound panels.
