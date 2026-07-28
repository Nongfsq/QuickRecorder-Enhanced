# Architecture Refactor Plan And Tasks

Status: **in progress**

Target architecture score: **96/100**

Execution model: incremental, behavior-preserving, package-first

## Goal

Create durable ownership and dependency boundaries so future feature work can
reuse established recording, archive, routing, file, and validation contracts.
The plan does not promise a final architecture forever; it minimizes recurring
decisions and defines evidence-based revisit triggers.

## Non-goals

- No full Rust rewrite.
- No visual redesign.
- No Debug app build, app replacement, automated app launch, or TCC reset.
- No deletion of legacy artifacts or migration data without explicit policy.
- No archive worker until continuation-after-exit is selected as a requirement.

## Constraints

- Preserve existing in-progress archive recovery changes.
- Keep SwiftUI/AppKit and Apple media frameworks native.
- Keep capture startup permission denial single-shot.
- Keep RNNoise as the pinned C implementation behind SwiftPM.
- Use synthetic, non-private media for integration fixtures.
- Public documentation must exclude machine paths, recordings, device details,
  credentials, and private experiment artifacts.

## Task board

### P0 — architecture baseline

- [x] **ARCH-001 — Audit existing boundaries.** Map lifecycle, capture, audio,
  video, QMA, archive, dependencies, security, CI, and documentation. Acceptance:
  current-system and technology reports contain evidence, risks, and unresolved
  runtime questions.
- [x] **ARCH-002 — Record target blueprint and ADRs.** Acceptance: selected
  design scores at least 95/100 and each major decision has rationale, rejected
  alternatives, and a revisit trigger.
- [x] **ARCH-003 — Enforce one application-delegate identity.** Replace the
  separately constructed delegate singleton with access to the adaptor-created
  delegate. Acceptance: all existing call sites resolve one identity; source
  parses; no app process is touched.
- [x] **ARCH-004 — Establish `RecordingDomain`.** Move stable recording enums
  out of the app shell and add typed session transitions with unit tests.
  Acceptance: package tests pass and the app uses a compatibility bridge during
  migration.
- [x] **ARCH-005 — Expand routine CI.** Test every committed local package and
  retain the public-tree gate. Acceptance: workflow includes RNNoise,
  ArchiveJobCore, and RecordingDomain tests.

### P1 — recording ownership

- [x] **ARCH-101 — Characterize effective preferences.** Add fixtures for
  defaults, validation, and request snapshots. Acceptance: one typed schema is
  authoritative and changes apply to the next session. `UserDefaults` suite
  fixtures cover normalized screen and iDevice snapshots.
- [x] **ARCH-102 — Introduce typed recording requests.** Replace string modes
  and selector-to-global mutation with `RecordingRequest` adapters. Acceptance:
  UI, hotkey, and AppleScript entry routes produce equivalent requests. Typed
  production routes share one adapter; the Objective-C selector retains a tested
  legacy-string compatibility facade.
- [x] **ARCH-103 — Create a single session owner.** Wrap stream, writer, audio,
  pause timeline, and teardown behind one actor or serial executor. Acceptance:
  no sample callback mutates writer state outside the owner; stress tests show
  ordered transitions. The serial media owner now orders writer inputs, all
  sample sources, per-track pause timelines, flushing, and asynchronous teardown.
- [x] **ARCH-104 — Extract pure media policies.** Move dimension, bitrate,
  adaptive-VFR, and pause timeline policy into RecordingDomain. Acceptance:
  deterministic boundary tests cover invalid values and timing edges. Dimension,
  bitrate, adaptive-VFR, per-track pause, and cross-sample-rate render-duration
  policies are integrated and package-tested.
- [x] **ARCH-105 — Extract finalization.** Return typed artifacts from writer,
  remix, QMA, and device paths. Acceptance: outcome matrix has parity for file,
  preview eligibility, notification, trim, and archive dispatch.
- [x] **ARCH-106 — Remove recording globals.** Migrate `SCContext` field groups
  into session/catalog/finalizer owners. Acceptance: remaining static members
  are immutable constants or a temporary facade with a removal task.
- [ ] **ARCH-107 — Remove compatibility facades.** Migrate the remaining
  `SCContext` forwarding call sites to session/catalog/finalizer owners, then
  delete the facades. Acceptance: no mutable recording state is exposed through
  `SCContext`; this is cleanup after the ownership transfer, not a new behavior.

### P2 — routing, archive, and infrastructure

- [ ] **ARCH-201 — Typed routes and windows.** Replace localized-title lookup
  with stable route/window IDs and coordinator ownership. Acceptance: multi-window
  localization tests leave no orphan monitors or panels. Progress: a role-aware
  placement coordinator now keeps Settings and ordinary user windows reachable
  across display changes; localized-title routing and complete window ownership
  remain open.
- [ ] **ARCH-202 — Capture catalog boundary.** Provide immutable shareable-content
  snapshots and cancellable thumbnails. Acceptance: selectors no longer mutate
  a shared catalog singleton.
- [ ] **ARCH-203 — Split archive model and engine.** Make UI state `MainActor`;
  isolate persistence/process/validation behind protocols. Acceptance: fake
  process and repository tests cover duplicate start and transition ordering.
- [ ] **ARCH-204 — Complete recovery semantics.** Connect every recovery
  disposition to production actions; surface load issues; validate all schema
  and path fixtures. Acceptance: full on-disk recovery matrix passes. Progress:
  production UI now consumes the classifier, validates recovered temporary or
  final output, surfaces manifest-load issues, and refuses recovery while an
  orphan process still has the candidate output open; the full fixture matrix
  remains open.
- [ ] **ARCH-205 — Bounded archive cancellation.** Own process groups, check
  cancellation at preparing/encoding/verifying/publish boundaries, and escalate
  after a deadline. Acceptance: a child that ignores graceful termination cannot
  block app termination indefinitely. Progress: encoding and validation now
  observe cancellation, helper subprocesses have timeouts, and FFmpeg escalates
  from terminate to `SIGKILL`; process-group ownership and the ignoring-child
  integration fixture remain open.
- [x] **ARCH-206 — Decide independent worker.** Product decision: archives
  continue after UI exit, or orderly wait/cancel only. Acceptance: ADR status is
  accepted. ADR-0003 selects orderly wait or bounded cancellation; continuation
  after exit remains out of scope, so no independent-worker lease is required.
- [ ] **ARCH-207 — Centralize file capabilities.** Validate destinations,
  symlinks, permissions, atomic replacement, Trash deletion, and retention.
  Acceptance: tampered manifests cannot direct writes outside granted policy.
- [ ] **ARCH-208 — Harden runtime trust.** Production executes only a sealed or
  separately signed verified runtime; release resources are explicitly listed.
  Acceptance: substitution and dirty-resource tests fail closed.
- [ ] **ARCH-209 — Add diagnostics.** Define privacy-aware OSLog categories,
  signposts, bounded logs, and purge policy. Acceptance: failures distinguish
  missing diagnostics from successful no-error cases without exposing paths by
  default.

### P3 — delivery gates

- [ ] **ARCH-301 — Synthetic media integration suite.** Cover A/V sync,
  pause/resume, stop races, remux failure, QMA lengths/rates, and archive crash
  recovery.
- [ ] **ARCH-302 — Dependency and license governance.** Pin dependencies,
  inventory licenses and SBOM data, and verify lockfile drift.
- [ ] **ARCH-303 — Reproducible universal archive runtime.** Build both
  architectures from pinned inputs with notices, source obligations, signatures,
  and provenance free of local paths.
- [ ] **ARCH-304 — Signed Release application gate.** With explicit
  authorization, compile and statically inspect one signed Universal Release;
  human-run installed-app validation supplies permission and runtime evidence.

## Implementation rules

1. Add characterization tests before moving ordering-sensitive media code.
2. One change owns one seam; do not combine session, finalization, and worker
   migrations.
3. Keep compatibility adapters short-lived and assign their removal to a task.
4. Persisted schema changes are additive and fixture-tested.
5. No phase is complete from source parsing alone when runtime behavior is part
   of its acceptance criteria.

## Current execution slice

Completed execution slices:

- ARCH-003 through ARCH-005: delegate identity, RecordingDomain foundation,
  and local-package CI.
- ARCH-101 through ARCH-106: immutable settings and typed routes feed one
  lock-protected session coordinator; a serial media owner owns all writer,
  sample, pause, and asynchronous finalization ordering; domain tests cover the
  production policy matrix. `SCContext` now contains temporary forwarding
  facades whose deletion is tracked by ARCH-107.
- ARCH-204 through ARCH-206: recovery actions, bounded cancellation, publish
  ordering, child lifetime, and the orderly wait/cancel product decision are
  implemented. Full fixture and installed interaction coverage remains in the
  P2/P3 quality tasks.

## Verification checklist

- [x] `RecordingDomain` debug and release package tests pass.
- [x] `ArchiveJobCore` debug and release package tests pass.
- [x] `RNNoiseProcessor` debug and release package tests pass.
- [x] `WindowPlacementCore` debug and release package tests pass.
- [x] Swift source parse checks pass.
- [x] plist and localization files pass `plutil`.
- [x] Xcode project listing resolves the local package graph.
- [x] public-tree and whitespace checks pass.
- [x] signed Universal Release build and static bundle inspection pass.
- [x] synthetic H.264/AAC to AV1/AAC archive smoke passes codec, dimensions,
  channel/rate, and monotonic video-packet checks.
- [x] the authorized installed Release launches to the main panel and opens the
  Preferences route without a crash; no ScreenCaptureKit permission retry or
  TCC mutation occurs.

The P1 domain slice additionally passes 20 RecordingDomain tests in both Debug
and Release configurations plus a signed Universal app build. Real recording,
pause/resume, active-recording Quit, and permission interaction remain explicit
human smoke items under ARCH-301/ARCH-304.

## Completion definition

The architecture program is complete only when P0–P3 acceptance evidence is
recorded. This initial slice is complete when ARCH-003–005 and the routine
verification checklist pass; later tasks remain explicitly open rather than
being implied complete.
