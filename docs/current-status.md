# Current Status

## Released baseline

The latest downloadable checkpoint is `v1.7.0-alpha.1`. The later
`v1.7.0-alpha.2` prerelease was withdrawn because its binary preceded the
completed Stage 0 recording-finalization and archive-exit fixes. The current
working line is therefore unreleased until its signed Universal application and
DMG pass the full Stage 0 gate.

## Active engineering work

The current development line continues the modular architecture migration. The
archive recovery, recording policy, and window placement foundations remain the
active development baseline. Live sample append, writer ownership, writer
teardown, and typed finalization now share one recording-session boundary in the
current working line.

The architecture direction is a native Swift modular monolith:

- SwiftUI and AppKit remain the application shell;
- ScreenCaptureKit, AVFoundation, VideoToolbox, and Core Audio remain native
  platform adapters;
- deterministic state machines, settings snapshots, manifests, path policy,
  and command policy move into testable local Swift packages;
- RNNoise remains its pinned C implementation behind a Swift package;
- FFmpeg/SVT-AV1 remain external media workers, not code to rewrite in Swift or
  Rust.

The recording-domain migration snapshots normalized preferences at session
creation and centralizes request, bitrate, adaptive-VFR, pause, and finalization
policy behind package tests. A lock-protected coordinator owns request identity
and legal lifecycle transitions, while a serial media owner orders sample
append, writer inputs, pause state, flushing, and writer teardown. Screen,
system-audio, remix, MP3, QMA, and iDevice paths report a common typed outcome;
the session does not return to idle before that outcome is consumed.

Ordinary user windows now use a role-aware placement policy. Settings, the main
panel, archive/recovery/editor content, document windows, and movable utility
panels are revalidated against live display visible frames when monitors are
removed or rearranged. Capture-bound overlays and mouse/capture transients are
explicitly excluded so recovery cannot corrupt recording geometry. The pure
policy is covered by Debug and Release package tests; real monitor disconnect
behavior remains a human-run installed-app validation.

Archive jobs now persist versioned state, defer orderly application termination
until work finishes or bounded cancellation completes, and expose recovery
actions derived from the on-disk source/output/temporary-file state. Recovery
refuses to replace or remove a temporary output while another process still has
it open. Validation subprocesses are cancellable and time-bounded, and a child
that ignores graceful termination is force-stopped after a short deadline.
Continuation after application exit remains explicitly out of scope: normal
quit waits or cancels, while crash/force-quit recovery validates existing output
before publishing or restarting it.

The accepted product contract is orderly wait or bounded cancellation; archive
jobs do not intentionally continue after the QuickRecorder UI process exits.
An active recording is finalized first, so any automatic archive it creates is
included in the same termination decision.

## Known delivery limits

- The app target has no committed application test target.
- Package tests cover RNNoise, recording-domain policy, archive recovery, and
  window placement. The current working line passes a signed Universal Release
  compile and static bundle validation; installed UI, recording, and permission
  evidence is recorded only after the direct-replacement smoke gate.
- The optional FFmpeg runtime is not yet a reproducible, universal,
  release-signed supply chain.
- Developer ID signing, notarization, complete third-party notices, and a
  fork-owned update feed remain public binary release gates.

## Authority

User-visible behavior belongs in [features.md](features.md). Architecture and
engineering direction belong in [architecture](architecture/README.md).
Release requirements belong in [releases.md](releases.md) and
[building.md](building.md). Released changes belong in `CHANGELOG.md`.
