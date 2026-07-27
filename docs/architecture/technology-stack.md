# Technology Stack Assessment

## Recommendation

Keep Swift as the primary language and keep the product a native macOS
application. Do not perform a Rust rewrite.

Swift is not the cause of the current coupling. The problems are mutable global
state, duplicate lifecycle ownership, missing state machines, and mixed UI,
media, persistence, and process responsibilities. Rewriting those structures
in Rust would preserve the design problems while adding FFI, IPC, packaging,
debugging, and hiring costs.

## Stack inventory

| Layer | Current technology | Decision |
|---|---|---|
| Application lifecycle and UI | SwiftUI + AppKit | Keep; introduce one coordinator and typed routes |
| Screen capture | ScreenCaptureKit | Keep native; isolate behind capture catalog and engine adapters |
| Media writing and editing | AVFoundation / AVFAudio / CoreMedia | Keep native; serialize ownership and expose typed outcomes |
| Hardware encoding policy | VideoToolbox through AVAssetWriter | Keep; measure before changing |
| Camera and device capture | AVFoundation / CoreMediaIO | Keep; converge on common artifact contract |
| Audio processing | AVAudioEngine / AECAudioStream | Keep as platform adapters |
| Noise suppression | RNNoise C behind SwiftPM | Keep pinned implementation; optimize buffers only from measurements |
| Archive encoding and probing | FFmpeg / ffprobe / SVT-AV1 child processes | Keep external; harden trust, supervision, and cancellation |
| Domain and persistence policy | Swift Foundation packages | Expand for recording, archive, process, and filesystem policy |
| Settings | UserDefaults / AppStorage | Keep storage; centralize schema and create immutable snapshots |
| Diagnostics | print statements + archive files | Move to privacy-aware OSLog categories and signposts |
| Build and dependencies | Xcode + SwiftPM | Keep; pin dependencies and expand CI/package tests |

## Why native Swift is the best fit

- ScreenCaptureKit, AVFoundation, AppKit, SwiftUI, ServiceManagement, TCC, and
  code-signing behavior are the product's primary integration surface.
- SwiftPM already provides the desired modularization and deterministic unit
  testing without creating a second runtime.
- The CPU-heavy work is already delegated to platform encoders, RNNoise C, and
  FFmpeg/SVT-AV1. Orchestration language choice is not the dominant performance
  factor.
- A single-language application shell gives better crash symbols, actor/queue
  ownership, native API evolution, accessibility, lifecycle, and signing
  integration.

## Where Rust could become justified

Rust should be reconsidered only if evidence satisfies one of these triggers:

1. QuickRecorder gains a real cross-platform capture or media-worker product;
2. a separately versioned worker needs memory-safe parsers or algorithms not
   available as suitable C, C++, Swift, or subprocess components;
3. repeatable profiling identifies a CPU or memory bottleneck in pure Swift
   code and an isolated Rust component demonstrates a material end-to-end win;
4. an existing Rust library provides unique capability whose FFI and supply
   chain are cheaper than a native implementation.

Even then, prefer an isolated component with a stable protocol. Do not rewrite
the AppKit/SwiftUI application or Apple capture adapters.

## Independent archive worker decision

An independent worker may be justified, but it should initially be Swift.

- If archives must continue after the UI exits, use a separately signed Swift
  executable or XPC/helper boundary sharing the archive domain schema.
- The worker exclusively owns the child process group and a renewable job
  lease; the UI observes durable state and requests cancellation.
- If continuation after exit is not a requirement, keep encoding in-process,
  guarantee bounded cancellation and child cleanup, and provide explicit
  interrupted-job recovery.

This is a product requirement decision, not a language decision.

## Dependency strategy

- Replace moving branch requirements with reviewed tags or revisions.
- Preserve the committed resolution lock and fail validation on unintended
  changes.
- Maintain license and provenance inventory for Swift packages and media
  runtimes.
- Build release FFmpeg/SVT inputs from pinned recipes for both architectures;
  verify hashes, dylib closure, signatures, and corresponding-source duties.
- Production runtime resolution must not trust arbitrary user-writable binaries
  merely because they print expected capabilities.

## Revisit cadence

Review this stack decision only after a platform expansion, measured bottleneck,
or worker-isolation requirement changes. Ordinary feature growth is not a
rewrite trigger.
