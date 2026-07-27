# Architecture Blueprint: Multi-Display Window Recovery

## Summary

- Product goal: every user-facing QuickRecorder window remains reachable when displays are attached, removed, rearranged, mirrored, or made primary.
- Architecture type: existing-system feature/refactor.
- Selected stack: AppKit window coordination in the app target plus a pure Swift geometry policy with deterministic tests.
- Primary constraints: macOS 12.3+, mixed SwiftUI/AppKit ownership, negative global coordinates, system-restored Settings frames, and screen-bound recording overlays.
- Non-goals: no window UI redesign, no TCC changes, no general route-coordinator rewrite, and no forced recentering of already reachable windows.

## Research Findings

### Platform behavior

AppKit exposes the current display topology through `NSScreen.screens`; the first screen is the primary screen, while `NSScreen.main` follows the focused window and may differ. The array must not be cached because displays can be reconfigured dynamically. `visibleFrame` is the safe user-content rectangle after menu bar, Dock, and camera-housing exclusions, and it also must be read live.

`NSApplication.didChangeScreenParametersNotification` is posted after a display configuration change. It is the correct recovery trigger for disconnect, rearrangement, resolution, mirroring, and primary-display changes. Window frame autosave and SwiftUI scene restoration can reload coordinates from user defaults; therefore a previously valid frame may be outside every currently attached display.

Primary references:

- Apple, [NSScreen.screens](https://developer.apple.com/documentation/appkit/nsscreen/screens)
- Apple, [NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe)
- Apple, [NSApplication.didChangeScreenParametersNotification](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification)
- Apple, [NSWindow frame autosave](https://developer.apple.com/documentation/appkit/nswindow/setframeautosavename(_:))

### Current QuickRecorder behavior

| Window family | Current placement | Failure mode | Target policy |
|---|---|---|---|
| SwiftUI Settings | system frame restoration | old external-display coordinates reopen offscreen | register as a managed utility window and validate after restoration/open |
| Main recording panel | `center()` followed by `screen.frame` math | placement depends on AppKit-selected screen and ignores safe area | create on the current interaction screen and fit within `visibleFrame` |
| Archive, recovery, editor windows | mouse-screen coordinates and fixed 780×555 geometry | can be partially outside small displays; no disconnect recovery | fit on open; recover on topology changes |
| Document/QMA windows | SwiftUI document scene | system restoration can become stale | manage as standard user windows without changing document ownership |
| Camera/device/controller panels | mutable global AppKit windows | a panel can remain attached to a removed screen | recover only when visible and not intentionally screen-bound |
| Area selector, screen covers, countdown, capture outlines | explicit capture-display frames | blindly centering would corrupt capture semantics | close/recreate or rebind through the capture flow; exclude from generic rescue |
| Pointer, magnifier, preview toast | mouse/capture-relative transient frames | intended to cross display boundaries | exclude from persistent-window rescue |

The current implementation has no display-topology observer and no common definition of “reachable.” It also selects windows by localized titles in several places. This fix introduces stable window roles for placement without attempting the full route migration tracked by `ARCH-201`.

## Decisions

- Frontend/runtime: a `WindowPlacementCoordinator` on the main thread owns display-change observation and managed-window rescue. Why: `NSWindow` and `NSScreen` are AppKit state and must be handled at the application boundary. Rejected: view-local `onAppear` fixes (miss disconnects and duplicate policy). Revisit when: the deployment target supports a SwiftUI placement API that covers restored AppKit windows and live display removal.
- Backend/runtime: no service or helper process. Why: placement is synchronous UI policy. Rejected: persistent background agent (unnecessary authority and lifecycle complexity). Revisit when: N/A.
- Data/persistence: preserve AppKit/SwiftUI frame persistence, but validate the realized frame against live screens. Why: users keep useful placement while stale coordinates are repaired. Rejected: deleting all `NSWindow Frame` defaults (destructive and loses valid preferences). Revisit when: typed per-route placement persistence replaces system restoration.
- API/contracts: stable `WindowRole` classifies `recoverable`, `screenBound`, and `transient`; a pure policy accepts window frame, live visible frames, preferred display, and minimum reachable size. Why: role and geometry decisions become explicit and testable. Rejected: localized-title heuristics as the policy source. Revisit when: `ARCH-201` introduces typed routes and window IDs across the application.
- Auth/security: N/A — no new permissions, files, network, or user data.
- Testing: deterministic policy tests cover negative coordinates, external-display removal, partial visibility, oversized windows, and empty-screen defense; signed Release build covers integration. Why: display hardware is unsuitable as the sole regression test. Rejected: manual HDMI testing only. Revisit when: an application UI test target can simulate window movement.
- CI/CD and deploy: add the pure package to local-package CI, build a signed Universal Release, statically validate, then directly replace the authorized local installation without launching it. Rejected: Debug app launch or TCC reset. Revisit when: the public binary release gates are complete.
- Observability: debug-only concise recovery logging with role and display count, never file paths or display identities. Why: enough evidence for diagnosis without collecting private topology. Rejected: persistent telemetry. Revisit when: `ARCH-209` defines the project logging policy.
- Documentation: this blueprint, an ADR, and a numbered PLAN+TASK are the source of truth. Why: the policy is durable and affects future windows. Rejected: code-only behavior. Revisit when: window routing architecture changes.

## System Shape

- Runtime surfaces: SwiftUI Settings/DocumentGroup, AppKit-created main/archive/editor windows, recording overlays, and transient recording utilities.
- Module boundaries: `WindowPlacementCore` owns pure rectangle decisions; `WindowPlacementCoordinator` maps live `NSScreen`/`NSWindow` state and owns observers; creation sites assign roles and request placement.
- Data flow: window opens/becomes key or display topology changes → coordinator snapshots live visible frames → pure policy returns unchanged or corrected frame → coordinator applies only a necessary correction.
- External integrations: AppKit only.
- Background jobs/events: main-thread display-parameter notification; no persistent job.

## Scaffold Plan

- `Packages/WindowPlacementCore/`: pure geometry policy and tests; validate with `swift test` in Debug and Release.
- `QuickRecorder/Supports/WindowPlacementCoordinator.swift`: AppKit adapter, stable roles, exclusions, display observer; validate with signed app build.
- `QuickRecorder/QuickRecorderApp.swift`: coordinator lifecycle, Settings registration, and main-window placement.
- `QuickRecorder/ViewModel/ContentView.swift`: common placement for archive/editor windows while preserving explicit capture-screen windows.
- `.github/workflows/public-safety.yml`: package regression test.
- `docs/decisions/ADR-0005-multi-display-window-placement.md`: durable ownership and recovery decision.

## Migration and Rollout

- Current state → target state: scattered placement remains temporarily at capture-specific sites; ordinary user windows route through one coordinator and all visible recoverable windows are revalidated after topology changes.
- Staged rollout: land pure policy/tests; integrate coordinator; statically validate signed Universal Release; install locally; human HDMI/display test.
- Compatibility window: macOS 12.3+ AppKit APIs only; existing frame defaults remain readable and writable.
- Data migration: none. Existing defaults are not deleted.
- Rollback: revert coordinator integration and package references; no persistent schema rollback is needed.
- Kill switches: none required because correction runs only when a managed window is not meaningfully reachable.
- Rollback signal: a reachable window moves unexpectedly, a screen-bound overlay is relocated, or Settings cannot become key/front.

## Implementation Sequence

- Foundation: create and test the pure rectangle policy.
- First vertical slice: register Settings and prove an offscreen restored frame is recovered onto the primary visible frame.
- Hardening: cover main/archive/editor/document windows, observe display changes, and exclude screen-bound/transient windows.
- Launch gates: package tests, source/project validation, signed Universal Release, static bundle inspection, local replacement, and human multi-display smoke.

## Verification

- Unit/component tests: unchanged negative-coordinate placement, full external removal, insufficient titlebar visibility, oversized frame fitting, preferred-screen fallback, empty topology.
- API/contract tests: role classification and policy input/output contracts compile in Debug and Release.
- Integration/E2E tests: manual move Settings to external display → close → disconnect → reopen; disconnect while Settings/main window is visible; reconnect/rearrange without recentering reachable windows.
- Build/type/lint checks: all local package tests, Xcode project listing, Release Universal build, whitespace and public-tree checks.
- Deployment smoke: static signature, architecture, bundle identity, and embedded runtime validation; no automated app launch.
- Observability checks: recovery log occurs only when a frame changes.

## ADRs to Write

- ADR: Centralized role-aware multi-display window placement. Context/decision: pure geometry policy plus AppKit coordinator validates realized frames and display changes. Rejected: clearing defaults, per-view fixes, and global recentering. Revisit when: typed route/window ownership replaces title-based routing or SwiftUI provides equivalent backwards-compatible control.

## Risks And Assumptions

- Risks: treating overlays as normal windows would break capture geometry; correcting a merely unusual but reachable frame would fight user intent; SwiftUI may apply a restored frame after the first accessor callback.
- Assumptions: a reachable title/control region of at least 96×32 points is sufficient; if no screen meaningfully intersects a window, the primary screen is the deterministic fallback; ordinary new windows may prefer the pointer screen.
- Revisit triggers: simultaneous independent capture sessions, Stage Manager-specific failures, a new always-on-top panel family, or migration under `ARCH-201`.

## Handoff

- Assumptions with stated defaults: preserve any meaningfully reachable frame; primary display is the recovery default; Settings is always recoverable.
- Open questions: none blocking. Non-blocking manual validation requires the user's real monitor topology after installation.
- Non-goals: visual redesign, full typed routing, capture-coordinate rewrite, and state-default deletion.
- Status: blueprint written here; the paired PLAN+TASK authorizes the requested implementation sequence.
