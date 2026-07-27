# Architecture

QuickRecorder is a native macOS modular monolith. The architecture keeps
Apple-platform integration close to the app while extracting deterministic
policy and state into local Swift packages.

## Documents

- [Current system assessment](current-system.md)
- [Technology stack assessment](technology-stack.md)
- [Target architecture blueprint](target-architecture.md)
- [Refactor plan and tasks](refactor-plan.md)
- [Architecture decisions](../decisions/README.md)

## Durable rules

1. One application coordinator and one recording-session owner exist per app
   process.
2. Capture callbacks never own UI, preferences, notifications, or routing.
3. A recording uses an immutable settings snapshot.
4. Sample ingestion and writer teardown have one serialized owner.
5. Every capture backend returns the same typed artifact/failure contract.
6. Persisted schemas are versioned and migration-tested.
7. File deletion, replacement, and external-process execution pass through
   explicit policy boundaries.
8. Platform-independent policy is package-tested; application behavior has a
   separately authorized signed Release gate.

These rules reduce repeated architectural decisions, but they do not make the
architecture permanent. Each ADR defines evidence that would justify revisiting
its decision.
