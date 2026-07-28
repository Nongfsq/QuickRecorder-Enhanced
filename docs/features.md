# Features

## Recording

QuickRecorder Enhanced records screens, windows, applications, areas, cameras,
mobile devices, microphones, and supported system audio through macOS native
media frameworks.

The lecture preset favors readable text and manageable file sizes with HEVC,
15 FPS, adaptive VFR, and mono AAC audio.

## Microphone noise reduction

The microphone option uses a pinned local RNNoise package at 48 kHz mono. It
processes 480-sample frames and mixes 80% processed audio with 20% of the
time-aligned original signal. The pipeline compensates RNNoise's one-frame
latency before writing media timestamps.

System audio bypasses RNNoise. Acoustic echo cancellation and RNNoise are
mutually exclusive because they are separate microphone-processing paths.

## AV1 archive

Completed recordings can be archived with FFmpeg and SVT-AV1. The archive
subsystem preserves the source recording, reports progress, writes a job
manifest, and validates streams, duration, timestamps, and decode behavior.

The development line is adding versioned manifests, explicit interrupted-job
classification, task-owned temporary paths, recovery review, and coordinated
quit behavior. Recovery records can be removed individually or cleared in one
action without deleting source recordings or completed archives; cancelled and
dead missing-file records do not reopen the recovery window. These behaviors
remain development state until the validation gates in [testing.md](testing.md)
pass.

Generated FFmpeg binaries are not stored in Git. Developers can supply a local
runtime explicitly or build a package with the scripts under `Tools/Archive`.

## Permission behavior

ScreenCaptureKit content discovery is single-shot at startup. A denied request
returns unavailable immediately and is not retried automatically. Permission
requests should occur only after a user action.

## Application language

General Settings offers System Default, English, Simplified Chinese,
Traditional Chinese, and Italian. The choice is stored by QuickRecorder and
does not change the global macOS language order. SwiftUI content can update
immediately; restart QuickRecorder to apply the choice consistently to menus,
alerts, and windows that were already open.

Only complete localizations embedded in the signed application and declared in
the shipping locale manifest appear in the picker. QuickRecorder does not
download or execute runtime language packs.
