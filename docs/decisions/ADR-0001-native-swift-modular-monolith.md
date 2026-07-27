# ADR-0001: Native Swift Modular Monolith

Status: Accepted

## Context

QuickRecorder is a macOS recording product whose core integration surface is
SwiftUI, AppKit, ScreenCaptureKit, AVFoundation, VideoToolbox, Core Audio,
ServiceManagement, and macOS privacy and signing behavior. Current maintenance
problems come from mixed responsibilities and mutable global state. Expensive
DSP and encoding already run in RNNoise C, Apple codecs, and FFmpeg/SVT-AV1.

## Decision

Keep the application and orchestration in Swift. Use local Swift packages for
portable domain policy and app-owned adapters for Apple frameworks. Do not
rewrite the application in Rust.

## Rationale

This preserves first-class platform integration while directly addressing
ownership, state, and testability. It avoids introducing an FFI/IPC boundary
where no measured performance or portability benefit exists.

## Rejected alternatives

- Full Rust rewrite: high migration and integration cost; does not inherently
  fix lifecycle or state ownership.
- One XPC service per subsystem: operational complexity without current need.
- Keep one app module and only reorganize folders: improves navigation but not
  dependency enforcement or package testing.

## Consequences

Domain packages must remain independent of UI and capture frameworks. Native
engine packages may import Apple media frameworks but expose narrow protocols
and typed outcomes. Rust remains available for a future isolated component.

## Revisit trigger

Reconsider only for cross-platform product scope, a unique Rust library, or a
repeatable measured bottleneck where an isolated Rust component demonstrates a
material end-to-end benefit.
