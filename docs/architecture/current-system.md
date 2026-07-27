# Current System Assessment

## Summary

At the audit baseline, QuickRecorder was approximately ten thousand lines of
Swift in one application target plus RNNoiseProcessor and the provisional
ArchiveJobCore local package. Its platform choice was strong, but lifecycle and
concurrency ownership were weak. The most important issue was not file size: it
was that application routing, capture, sample delivery, finalization,
preferences, windows, and archive supervision shared mutable global or
singleton state.

Baseline architecture score: **58/100**. This score records the evidence before
the first refactor slice, not the target design. The first slice has since
removed the separately constructed delegate, added RecordingDomain as a third
local package, expanded package CI, introduced immutable normalized recording
requests, and extracted bitrate, adaptive-VFR, and pause-timeline policy.
Media-session ownership remains open.

| Dimension | Weight | Current | Main evidence |
|---|---:|---:|---|
| Platform and product fit | 15 | 14 | Native Apple media and UI frameworks fit the product |
| Boundary clarity | 15 | 5 | One app target; delegate and context span many concerns |
| State ownership | 15 | 3 | Dozens of static mutable recording fields |
| Concurrency safety | 15 | 4 | Concurrent media callbacks share writer and timeline state |
| Testability | 10 | 5 | Package tests exist, but no app or media integration target |
| Failure and recovery | 10 | 7 | Archive recovery is improving; capture finalization remains implicit |
| Security and privacy | 10 | 6 | Narrow entitlements, but runtime trust and metadata retention need policy |
| Delivery and observability | 5 | 2 | Minimal CI and mostly unstructured diagnostics |
| Documentation governance | 5 | 2 | Product docs exist; architecture/current-state records were absent |

## System shape

```text
SwiftUI scenes and AppKit windows
          |
          v
AppDelegate + global windows + raw UserDefaults
          |
          +--> selectors and capture catalog
          +--> SCContext static recording state
          +--> AVAssetWriter / audio / camera / device capture
          +--> finalization / preview / QMA / trimming
          +--> archive singleton / FFmpeg / persistence
```

The app target imports SwiftUI, AppKit, ScreenCaptureKit, AVFoundation,
VideoToolbox, CoreMediaIO, UserNotifications, ServiceManagement, and IOKit.
That is appropriate for an application shell, but those dependencies currently
reach deeply into domain decisions.

## Highest-risk boundaries

### Two application-delegate identities — addressed in the first slice

The audit found that SwiftUI created the lifecycle delegate through
`NSApplicationDelegateAdaptor` while the source also constructed
`AppDelegate.shared`. The first slice changed `shared` into an accessor for the
adaptor-installed delegate, eliminating the second constructed identity. A
future coordinator migration will remove delegate access from views entirely.

### Recording state is an implicit global state machine

`SCContext` owns roughly forty static mutable fields covering capture
selection, streams, writers, timestamps, pause flags, audio engines, paths, and
preview state. Screen and system-audio outputs use concurrent global queues;
microphone samples use additional realtime or serial callbacks. Writer inputs,
pause/resume state, and teardown do not have one explicit isolation boundary.

Apple documents that the queue supplied to ScreenCaptureKit receives stream
output and that all sample appends must finish before `AVAssetWriter` is asked
to finish. The current shape does not make that ordering enforceable.

### Finalization is branch-dependent

The stop path performs stream shutdown, microphone teardown, writer finish,
audio remix, UI updates, preview, trim, notification, archive dispatch, and
state reset. Device capture follows a different completion route. This makes
artifact outcome depend on which backend produced it.

### Preferences are not a schema

Dozens of string keys appear through repeated `AppStorage` declarations and
direct `UserDefaults` access. Defaults can differ by declaration, and capture
reads live values rather than a frozen session snapshot.

### Archive recovery is promising but not yet a worker boundary

The new archive domain package provides versioned manifests, explicit states,
recovery classification, and task-owned path checks. The application service
still combines UI observation, persistence, process supervision, runtime
installation, validation, notifications, and termination coordination.

Force-quit behavior remains especially important: a child FFmpeg process may
outlive the UI process unless process-group ownership or a leased independent
worker is established. Recovery must never delete or restart a temporary file
while another live worker owns it.

## Security and delivery observations

- The app uses hardened runtime and narrow camera/microphone entitlements, but
  is not App Sandbox enabled.
- AppleScript is an external control-plane adapter and should route through the
  same typed commands as UI and hotkeys.
- A mutable Application Support FFmpeg runtime is currently accepted by
  capability output rather than an immutable release trust policy.
- A folder resource can include ignored local runtime binaries in a local
  archive; release inputs must be explicitly enumerated and scanned.
- Archive manifests and logs contain private paths and command details. They
  need permissions, retention, redaction, and export policy.
- CI checks the public tree and RNNoise package only; it does not compile the
  app or test all local packages in the committed baseline.

## Falsifiable risk register

| Priority | Hypothesis | Discriminating validation |
|---|---|---|
| P0 | Delegate identity changes behavior by entry route | Compare delegate object identity for UI, hotkey, AppleScript, and sample callbacks |
| P0 | Stop races active sample callbacks | Stress stop/error/pause with writer-state instrumentation and Thread Sanitizer |
| P0 | Pause retains an audio gap or drift | Record tone and visual timecode across repeated pauses; inspect packet PTS and correlation |
| P0 | Force quit leaves an orphan archive encoder | Kill only the UI process and observe child identity, lease, and temp-file growth |
| P1 | Final artifact behavior differs by backend | Run an outcome matrix for screen, audio, QMA, camera, and device routes |
| P1 | Archive cancel during verification still publishes output | Slow validation and cancel at every state boundary |
| P1 | A substituted managed FFmpeg runtime executes | Replace it with a benign conforming marker in an isolated test account |
| P1 | Ignored local files enter a Release bundle | Compare clean and dirty staged Release resource inventories |

## Unresolved evidence

No app was built, installed, launched, stopped, or permission-probed for this
assessment. Runtime consequences of callback ordering, delegate identity,
pause timing, force-quit child behavior, and capture-backend parity remain
validation tasks rather than established facts.
