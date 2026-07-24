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

Generated FFmpeg binaries are not stored in Git. Developers can supply a local
runtime explicitly or build a package with the scripts under `Tools/Archive`.

## Permission behavior

ScreenCaptureKit content discovery is single-shot at startup. A denied request
returns unavailable immediately and is not retried automatically. Permission
requests should occur only after a user action.
