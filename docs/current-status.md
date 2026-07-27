# Current Status

## Released baseline

The latest published source checkpoint is `v1.7.0-alpha.1`. It establishes the
fork-owned bundle identity, native recording features, RNNoise microphone
processing, and an experimental AV1 archive workflow.

## Active engineering work

The current development line is establishing durable archive-job recovery and
a modular architecture baseline. Until that work passes its package, static,
media-integration, and signed Release gates, it is development state rather
than released behavior.

The architecture direction is a native Swift modular monolith:

- SwiftUI and AppKit remain the application shell;
- ScreenCaptureKit, AVFoundation, VideoToolbox, and Core Audio remain native
  platform adapters;
- deterministic state machines, settings snapshots, manifests, path policy,
  and command policy move into testable local Swift packages;
- RNNoise remains its pinned C implementation behind a Swift package;
- FFmpeg/SVT-AV1 remain external media workers, not code to rewrite in Swift or
  Rust.

The first recording-domain migration now snapshots normalized preferences at
session creation, maps all legacy recording entry strings into typed requests,
and centralizes bitrate, adaptive-VFR, and pause-timeline policy behind package
tests. The active media callback and writer teardown owner is the next migration
boundary and is not yet complete. A lock-protected coordinator now owns request
identity and legal lifecycle transitions, but sample append and writer resource
ownership have not yet moved out of the compatibility context.

Archive jobs now persist versioned state, defer orderly application termination
until work finishes or bounded cancellation completes, and expose recovery
actions derived from the on-disk source/output/temporary-file state. Recovery
refuses to replace or remove a temporary output while another process still has
it open. Validation subprocesses are cancellable and time-bounded, and a child
that ignores graceful termination is force-stopped after a short deadline.
Continuation after application exit remains explicitly out of scope: normal
quit waits or cancels, while crash/force-quit recovery validates existing output
before publishing or restarting it.

## Known delivery limits

- The app target has no committed application test target.
- Package tests cover RNNoise, recording-domain policy, and archive recovery
  logic. The current local checkpoint passes a signed Universal Release build,
  static bundle validation, and a synthetic AV1 media smoke test; installed UI,
  recording, and permission behavior still require human-run validation.
- The optional FFmpeg runtime is not yet a reproducible, universal,
  release-signed supply chain.
- Developer ID signing, notarization, complete third-party notices, and a
  fork-owned update feed remain public binary release gates.

## Authority

User-visible behavior belongs in [features.md](features.md). Architecture and
engineering direction belong in [architecture](architecture/README.md).
Release requirements belong in [releases.md](releases.md) and
[building.md](building.md). Released changes belong in `CHANGELOG.md`.
