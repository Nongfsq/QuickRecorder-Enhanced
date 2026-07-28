# Changelog

## Unreleased

## 1.7.0-alpha.4

- Restored codec, container, channel-mode, frame-rate, and bitrate identifiers
  to their standard verbatim forms in every language, and added a CI invariant
  preventing technical UI tokens such as `AAC`, `Mono`, `Opus`, and `VFR` from
  being semantically translated.

## 1.7.0-alpha.3 (withdrawn)

- Replaced drifting UI string tables with one validated String Catalog,
  completed the shipping locale key set, and added an app-owned language picker
  for System Default, English, Simplified Chinese, Traditional Chinese, and
  Italian.
- Routed every standalone SwiftUI host through the selected application locale
  and added CI coverage for static SwiftUI localization keys.
- Unified writer, microphone, pause-timeline, and teardown ownership behind one
  serial recording-session media owner.
- Added typed, awaitable recording finalization for screen capture, audio
  remix, MP3, QMA, and iDevice backends.
- Made application termination wait for active recording finalization before
  deciding whether to wait for or cancel newly created archive work.
- Hardened archive cancellation, recovery validation, publish commit ordering,
  and FFmpeg child lifetime handling.
- Prevented local ignored FFmpeg binaries from entering Release application
  resources until a reproducible Universal runtime is ready.

## 1.7.0-alpha.2 (withdrawn)

This prerelease was withdrawn because its binary preceded the completed Stage 0
recording-finalization and archive-exit fixes. The history below records what
the withdrawn checkpoint contained; it is not the current downloadable
baseline.

- Added durable archive manifests, interrupted-job recovery, stale-task cleanup,
  and safer application termination while archive work is active.
- Added clear recovery actions for abandoned or missing archive sources, with
  list cleanup that prevents deleted recordings from being recompressed.
- Introduced testable Swift packages for archive state, recording-domain
  policy, and role-aware window placement.
- Centralized typed recording requests, normalized preference snapshots,
  bitrate and adaptive-VFR policy, and session lifecycle transitions.
- Recovered ordinary app windows onto a live display after monitors are
  disconnected or rearranged, while preserving capture-bound overlay geometry.
- Fixed the SwiftUI app-delegate startup crash caused by duplicate lifecycle
  ownership.
- Fixed the main-panel Preferences command so it opens the settings window
  semantically instead of targeting a fragile menu index.
- Published an experimental, self-signed and unnotarized Universal DMG. The
  optional FFmpeg runtime is omitted until its Universal packaging and notices
  are release-ready.

## 1.7.0-alpha.1

- Added RNNoise microphone cleanup with a fixed 80/20 processed/dry mix.
- Added a lecture-oriented capture preset and adaptive VFR controls.
- Added validated AV1 post-record archival infrastructure.
- Fixed mono QMA audio export and mixed-track duration handling.
- Removed automatic retry behavior after ScreenCaptureKit permission denial.
- Established independent project documentation and release policy.
- Disabled the inherited upstream update feed pending a fork-owned signed feed.
- Published an experimental, self-signed Universal DMG for RNNoise and lecture
  recording tests; the optional FFmpeg runtime is not bundled in this alpha.
