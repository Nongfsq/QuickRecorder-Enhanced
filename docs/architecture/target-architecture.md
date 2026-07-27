# Target Architecture Blueprint

## Summary

Adopt a Swift modular monolith with one application coordinator, one
recording-session owner, pure package boundaries for deterministic policy, and
explicit adapters for Apple frameworks, files, external processes, and UI.

The selected design scores **96/100** against the project rubric. The score is
for the decision-complete target design, not a claim that the current code has
already reached it.

| Dimension | Weight | Target | Acceptance evidence |
|---|---:|---:|---|
| Platform and product fit | 15 | 15 | Native macOS APIs remain first-class |
| Boundary clarity | 15 | 15 | Dependency rules and owners documented and enforced |
| State ownership | 15 | 15 | One coordinator and one session owner; typed transitions |
| Concurrency safety | 15 | 14 | Serialized media sink; race/stress evidence required |
| Testability | 10 | 10 | Pure policies package-tested; adapters contract-tested |
| Failure and recovery | 10 | 9 | Typed finalization and leased archive recovery |
| Security and privacy | 10 | 9 | Runtime/file trust and retention controls |
| Delivery and observability | 5 | 4 | Expanded CI, OSLog, signposts, gated Release checks |
| Documentation governance | 5 | 5 | ADRs, current state, plan, and validation matrix |

## Decisions

### Native Swift modular monolith

- Decision: keep Swift, SwiftUI/AppKit, and Apple media frameworks; modularize
  with local Swift packages and app-owned adapters.
- Rationale: it matches the platform and removes the observed coupling without
  introducing FFI or a second runtime.
- Rejected: full Rust rewrite; a multi-process service for every subsystem;
  moving globals unchanged into packages.
- Revisit trigger: cross-platform product scope or a measured isolated
  bottleneck that an alternative implementation materially improves.

### One application and session owner

- Decision: the adaptor-created delegate is the only application delegate. A
  `MainActor` coordinator owns routes and user-facing state. A recording session
  actor/serial executor owns streams, writer inputs, timeline, and teardown.
- Rationale: invalid lifecycle combinations and cross-queue teardown become
  enforceable transitions.
- Rejected: canonicalizing a separately constructed `AppDelegate.shared`; one
  singleton each for stream, writer, and audio.
- Revisit trigger: simultaneous independent recording sessions become a product
  requirement.

### Immutable requests and typed outcomes

- Decision: snapshot preferences into `RecordingRequest`; all backends return
  `RecordingArtifact` or `RecordingFailure`; finalization is a separate state
  machine.
- Rationale: a session cannot change configuration mid-flight, and every
  capture route shares completion semantics.
- Rejected: direct `UserDefaults` reads in hot paths and branch-specific UI
  completion callbacks.
- Revisit trigger: settings explicitly gain supported live-reconfiguration
  semantics.

### Durable archive ownership

- Decision: manifests are versioned domain contracts; process supervision and
  filesystem policy are non-UI services; UI consumes immutable state. Use a
  leased independent Swift worker only if continuation after UI exit is chosen.
- Rationale: normal quit, crash recovery, cancellation, and process ownership
  require one source of truth.
- Rejected: Rust orchestration and blind restart of any nonterminal manifest.
- Revisit trigger: continuation-after-exit or stronger untrusted-media isolation
  becomes a confirmed product requirement.

## System Shape

```text
SwiftUI / AppKit views
        |
        v
ApplicationCoordinator (@MainActor)
  |         |             |                |
  v         v             v                v
Routes   Preferences   Recording       ArchiveJobsModel
                    Application Service     |
                         |                   v
                         v             Archive Engine
                 RecordingEngine       + Process Runner
                 (one session owner)    + Manifest Repository
                  |      |      |       + Filesystem Policy
                  v      v      v
                SCK   AVFoundation   RNNoise

Pure Swift packages:
RecordingDomain | ArchiveJobCore | MediaProcessKit
```

### Dependency rules

- Views depend on coordinators and immutable view state, never on media writer
  objects or raw process handles.
- Coordinators depend on protocols, never on global platform state.
- Engines may import Apple media frameworks but never SwiftUI, AppKit windows,
  `AppStorage`, alerts, notifications, or application termination APIs.
- Domain packages import Foundation only when necessary and never import UI or
  capture frameworks.
- Persistence repositories own schema codecs and atomic transition rules.
- File operations receive policy-validated capabilities, not arbitrary paths
  decoded directly from mutable manifests.

### Proposed modules

| Module | Owns | Must not own |
|---|---|---|
| `RecordingDomain` | modes, settings snapshot, requests, state transitions, artifacts, pure bitrate/VFR/timeline policy | AppKit, SwiftUI, SCK objects, writers |
| `RecordingEngine` | one active SCK/AVFoundation session, serialized sample sink, pause timeline, stop/teardown | windows, alerts, preferences, notifications |
| `CaptureCatalog` | permission-aware content snapshots and cancellable thumbnails | recording writers or UI routes |
| `MediaFinalization` | remix, export, QMA creation, cleanup policy, typed final outcome | preview windows or archive UI |
| `ArchiveJobCore` | manifest schema, legal states, recovery disposition, task ownership | Process, SwiftUI, notifications |
| `MediaProcessKit` | child process events, process groups, leases, bounded cancellation | archive UI or recording preferences |
| `ArchiveEngine` | runtime trust, command policy, encode, validate, publish | AppKit termination or observable UI state |
| App target | lifecycle, routes, views, notifications, platform adapters | portable domain policy |

## Scaffold Plan

```text
Packages/
  RecordingDomain/
  ArchiveJobCore/
  MediaProcessKit/                 # later phase
QuickRecorder/
  Application/
    ApplicationCoordinator.swift
    AppRoute.swift
    ApplicationTerminationCoordinator.swift
  Recording/
    RecordingEngine.swift
    RecordingSession.swift
    CaptureCatalog.swift
    RecordingPreferencesStore.swift
  Finalization/
    MediaFinalizer.swift
  Archive/
    ArchiveEngine.swift
    ArchiveJobsModel.swift
  Infrastructure/
    FilePolicy.swift
    Diagnostics.swift
```

Only create a module when a real vertical slice moves into it. Empty layers and
one-type micro-packages are not architecture progress.

## Migration and Rollout

Use a strangler migration. Preserve behavior behind adapters, add
characterization tests, then move ownership one seam at a time.

1. Establish documents, package CI, a pure recording domain, and one delegate
   identity.
2. Introduce typed requests and a preferences snapshot while adapting into the
   existing recording entry point.
3. Create one serialized recording-session owner; move writer and timeline
   fields from global state in groups.
4. Extract finalization and converge device capture on the artifact contract.
5. Extract capture catalog and typed routes; remove title-based window control.
6. Split archive UI state from process/persistence engine; enforce recovery
   classification and bounded cancellation.
7. Decide continuation-after-exit. Add a leased Swift worker only if required.
8. Remove the remaining global compatibility facade after runtime parity gates.

Each phase must be independently releasable or revertible. Persisted schema
changes are additive and fixture-tested. Application Support migration must
preserve legacy jobs until explicit user-approved cleanup.

## Implementation Sequence

The authoritative task IDs and acceptance criteria are in
[refactor-plan.md](refactor-plan.md). P0 tasks establish ownership and test
boundaries; P1 tasks migrate recording/finalization; P2 tasks harden archive,
routing, observability, and delivery.

## Verification

- Package tests for every state machine, schema, settings snapshot, path rule,
  command policy, and timeline policy.
- Synthetic-media integration for timestamp monotonicity, pause synchronization,
  stop races, remux failures, QMA parity, and archive recovery.
- Stress and Thread Sanitizer evidence for session ownership transitions.
- Clean-versus-dirty Release resource inventory and runtime trust checks.
- Signed Universal Release integration only at the explicit application gate.
- Human validation of permissions and installed-app routes without TCC reset.

## ADRs to Write

Initial decisions are recorded under `docs/decisions/`:

- Swift modular monolith and Rust decision;
- single application and recording-session owner;
- archive continuation and worker boundary;
- FFmpeg runtime trust and release artifact boundary.

Future ADRs should cover preference schema, file capabilities/deletion, privacy
retention, typed routing, and observability once their implementation phase
starts.

## Risks And Assumptions

- Actor or queue isolation can change media backpressure and ordering. Migration
  requires timestamp and dropped-frame evidence, not compilation alone.
- The current stop sequence contains ordering-sensitive asynchronous work.
- App Sandbox adoption is not assumed; it requires a separate compatibility
  investigation for recording and file workflows.
- Archive continuation after UI exit is intentionally unresolved until the
  product requirement is selected.
- A 96/100 design does not eliminate future architecture work. It fixes today's
  repeated boundary decisions and supplies explicit triggers for future change.

## Handoff

Begin with the P0 tasks in the refactor plan. Do not mix recording-session
ownership migration with archive worker extraction in the same change. Keep
the existing archive recovery work intact, but treat it as provisional until
its recovery matrix and process-ownership gaps are closed.
