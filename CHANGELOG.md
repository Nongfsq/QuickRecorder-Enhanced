# Changelog

## 1.7.0-alpha.2

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
