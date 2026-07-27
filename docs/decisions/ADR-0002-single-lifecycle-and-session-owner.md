# ADR-0002: Single Lifecycle And Recording-Session Owner

Status: Accepted

## Context

The application currently has an adaptor-created application delegate and a
separately constructed delegate singleton. Recording resources and lifecycle
flags are also spread across static state while callbacks arrive on multiple
queues.

## Decision

Use the adaptor-created object as the only application delegate. A `MainActor`
application coordinator owns user-facing state and routes. Each recording uses
one actor or serial executor that owns streams, writer inputs, timeline state,
sample ingestion, and teardown.

## Rationale

One owner makes lifecycle identity explicit and lets the code enforce that all
sample appends finish before writer finalization. Typed session transitions
replace invalid combinations of optional global fields.

## Rejected alternatives

- Make a separately constructed singleton the canonical delegate: conflicts
  with SwiftUI lifecycle ownership.
- Create independent stream, writer, audio, and pause singletons: preserves
  multi-owner teardown.
- Add locks around every static field: difficult to reason about and does not
  establish a legal state machine.

## Consequences

Selectors, hotkeys, and AppleScript become command adapters. Settings are
snapshotted per session. Migration requires media timing and stop-race evidence
because isolation can affect backpressure and callback ordering.

## Revisit trigger

Revisit the one-session assumption if simultaneous independent recordings
become a supported product feature. Each session must still retain one owner.
