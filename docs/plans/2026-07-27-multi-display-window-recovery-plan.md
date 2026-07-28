# Multi-Display Window Recovery Plan and Tasks

Status: **approved for execution by the user's combined plan-and-execute request**

## Summary

QuickRecorder must never leave an ordinary user-facing window on a display that no longer exists. The essential promise is simple: opening Settings, the main panel, recovery, archive, editor, or document windows always produces a reachable window, while recording overlays remain precisely bound to their selected capture display.

## Current Reality

- SwiftUI persists the Settings frame under `com_apple_SwiftUI_Settings_window`; the saved rectangle may describe a disconnected display.
- Window placement is scattered across `QuickRecorderApp.swift`, `ContentView.swift`, `SCContext.swift`, and overlay code.
- The app does not observe display-parameter changes.
- Several ordinary windows use full screen frames rather than safe visible frames.
- Capture overlays and ordinary utility windows have different semantics but no explicit role model.

## Architecture Decisions

- A pure `WindowPlacementCore` package owns rectangle fitting and meaningful-visibility rules.
- A main-thread AppKit coordinator owns live screen snapshots, role registration, display-change observation, and frame application.
- Ordinary windows are recoverable; capture overlays and mouse/capture transients are excluded.
- Existing AppKit/SwiftUI persistence remains intact; stale realized frames are corrected instead of deleting defaults.
- Already reachable windows never move solely because the display topology changed.

## Frontend Workstream

- Settings registers through its existing `WindowAccessor` and is checked after SwiftUI restoration settles.
- Main and common content windows request role-aware placement before ordering front.
- Visible recoverable windows are checked after monitor attach/detach/rearrangement.
- No new dialog, preference, or user-facing control is introduced.

## Backend/API/Data Workstream

N/A — no backend, API, database, or persisted schema changes.

## Analytics/Observability/Security Considerations

- No telemetry or new permission.
- Debug logging records only that a role was recovered and the number of active screens.
- Display names, IDs, coordinates, file paths, and recording details are not persisted in new storage.

## Migration Order

1. Add the pure package and tests.
2. Add the AppKit coordinator and stable roles.
3. Integrate Settings and ordinary windows.
4. Register display-change observation and verify exclusions.
5. Build, install, and perform human multi-display validation.

## Rollout, Compatibility, And Rollback Notes

- Compatible with macOS 12.3+ and existing frame defaults.
- No migration or default deletion occurs.
- Roll back by reverting the coordinator/package integration; persisted state remains valid.
- Do not launch the app automatically after installation and do not alter TCC.

## Test And QA Plan

- Unit: negative monitor coordinates remain valid; removed external coordinates recover; partial visibility threshold; oversized windows fit; primary/preferred fallback; no-screen defense.
- Static integration: package Debug/Release tests, Swift parsing/type checking through Xcode, project package resolution, public-tree and whitespace checks.
- Release: signed Universal build and static bundle inspection.
- Human smoke: move Settings to external monitor, close it, disconnect monitor, reopen; repeat with window visible during disconnect; confirm a still-reachable window is not recentered.

## Tasks

### WINDOW-001: Add deterministic placement policy

- Status: complete — 6 Debug and 6 Release policy tests pass.

- Depends on: none
- Files: `Packages/WindowPlacementCore/Package.swift`, `Packages/WindowPlacementCore/Sources/WindowPlacementCore/WindowPlacementPolicy.swift`, `Packages/WindowPlacementCore/Tests/WindowPlacementCoreTests/WindowPlacementPolicyTests.swift`
- Change: define meaningful visibility, screen selection, fit/clamp, and unchanged-frame behavior using pure rectangles.
- Acceptance: all specified multi-display and oversized-frame cases return deterministic frames without importing AppKit.
- Validation: run `swift test` and `swift test -c release` in the package.

### WINDOW-002: Add AppKit window placement coordinator

- Status: complete — Xcode resolves the package and the Universal Release app compiles.

- Depends on: WINDOW-001
- Files: `QuickRecorder/Supports/WindowPlacementCoordinator.swift`, `QuickRecorder.xcodeproj/project.pbxproj`
- Change: introduce stable window roles, register recoverable windows, observe display topology and key-window changes, map live visible frames into the pure policy, and exclude capture-bound/transient windows.
- Acceptance: the coordinator changes only unreachable recoverable windows and uses the primary visible frame as deterministic recovery fallback.
- Validation: resolve the Xcode project and compile a Release app using the package dependency.

### WINDOW-003: Integrate Settings and ordinary window creation

- Status: complete — integration compiles and the installed app contains the signed implementation; human display smoke remains below.

- Depends on: WINDOW-002
- Files: `QuickRecorder/QuickRecorderApp.swift`, `QuickRecorder/ViewModel/ContentView.swift`, `QuickRecorder/Supports/WindowAccessor.swift`
- Change: start the coordinator at launch; register and recover Settings after restoration; place main, archive, recovery, and editor windows through the common policy before presentation.
- Acceptance: Settings and common user windows open on a live visible frame; reachable external-screen windows retain their position.
- Validation: signed Release build plus manual Settings/main-window monitor-disconnect smoke.

### WINDOW-004: Cover live topology changes without disturbing capture geometry

- Status: complete for implementation and automated validation; human disconnect/reconnect validation remains pending.

- Depends on: WINDOW-003
- Files: `QuickRecorder/Supports/WindowPlacementCoordinator.swift`, capture/window creation sites as proven necessary by audit
- Change: revalidate visible recoverable windows on `didChangeScreenParametersNotification`; explicitly classify screen-bound and transient global windows so they are never generically centered.
- Acceptance: disconnecting a display rescues visible ordinary windows; selectors, outlines, pointer, magnifier, countdown, and preview retain their capture/mouse semantics.
- Validation: policy tests plus manual disconnect/reconnect/rearrange matrix.

### WINDOW-005: Document, release-validate, install, and close out

- Status: complete — signed Universal Release installed locally without launch or TCC changes.

- Depends on: WINDOW-004
- Files: `.github/workflows/public-safety.yml`, `docs/architecture/2026-07-27-multi-display-window-recovery-blueprint.md`, `docs/decisions/ADR-0005-multi-display-window-placement.md`, `docs/architecture/README.md`, `docs/decisions/README.md`, `docs/current-status.md`, this plan
- Change: add package CI, record the durable decision and evidence, build one signed Universal Release, statically validate it, and directly replace the authorized local app without a backup or automated launch.
- Acceptance: all automated gates pass, the installed bundle is signed Universal, documentation reflects remaining human validation, and no runnable build copies remain.
- Validation: project checks, package tests, Release build, signature/architecture inspection, public-tree check, and process/candidate audit.

## Handoff

### Execution evidence

- `WindowPlacementCore`: 6/6 Debug and 6/6 Release tests passed.
- Existing packages: `ArchiveJobCore` 10/10, `RecordingDomain` 11/11, and `RNNoiseProcessor` 2/2 passed in both Debug and Release.
- Xcode resolved all local and remote packages and produced a signed Universal (`arm64`, `x86_64`) Release application.
- The built and installed bundles passed strict deep code-signature validation and binary comparison.
- `/Applications/QuickRecorder.app` was replaced directly; QuickRecorder was not launched, TCC was not changed, and no backup or temporary runnable app remains.
- Xcode emitted existing Swift 6 Sendable warnings in selector view models; this window-placement change introduced no build error or new warning category.

- Assumptions: 96×32 points is the default meaningful reachable region; the primary display is the recovery fallback; pointer screen is only a preference for newly created ordinary windows.
- Non-goals: UI redesign, full `ARCH-201` route migration, TCC reset, Debug app launch, and rewriting capture coordinate transforms.
- Rollback: revert WINDOW-002 through WINDOW-004; WINDOW-001 can remain as unused pure policy or be reverted independently.
- Status: implementation, automated validation, documentation, and local installation are complete. Human multi-display smoke is the only remaining validation.
