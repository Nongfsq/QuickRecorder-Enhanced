# Architecture Decision Records

ADRs capture durable technical choices and the evidence that would justify
changing them.

| ADR | Status | Decision |
|---|---|---|
| [ADR-0001](ADR-0001-native-swift-modular-monolith.md) | Accepted | Native Swift modular monolith; no Rust rewrite |
| [ADR-0002](ADR-0002-single-lifecycle-and-session-owner.md) | Accepted | One app delegate and one recording-session owner |
| [ADR-0003](ADR-0003-archive-worker-boundary.md) | Accepted | Wait or cancel active archive work before application exit |
| [ADR-0004](ADR-0004-ffmpeg-runtime-trust.md) | Accepted | Production media runtime must be immutable and verified |
| [ADR-0005](ADR-0005-multi-display-window-placement.md) | Accepted | Role-aware recovery keeps ordinary windows reachable across display changes |
| [ADR-0009](ADR-0009-signed-string-catalog-localization.md) | Accepted | Signed String Catalog with app-owned language selection |

An ADR is amended only for clarification. A changed decision receives a new ADR
that marks the old record superseded.
