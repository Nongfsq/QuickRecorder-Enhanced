# ADR-0003: Archive Worker Boundary

Status: Proposed

## Context

Orderly termination can wait for or cancel an in-process FFmpeg job. A crash or
force quit may leave child-process ownership ambiguous. Continuing archives
after the UI exits requires a different lifecycle contract than orderly
wait-or-cancel behavior.

## Proposed decision

First choose the product contract:

- **Wait or cancel:** keep archive execution in-process, own the process group,
  make cancellation bounded, and recover only after proving no worker lives.
- **Continue after exit:** add a separately signed Swift executable or XPC/helper
  that exclusively owns process groups and renewable job leases. The UI is a
  client of durable manifests/events.

Do not use Rust merely to create this boundary.

## Rationale

The worker decision changes installation, signing, IPC, crash recovery,
security, and UX. It should follow an explicit product requirement rather than
emerge accidentally from child-process behavior.

## Rejected alternatives

- Blindly resume every nonterminal manifest: may conflict with a surviving
  process.
- Let unmanaged FFmpeg children outlive the app: no reliable ownership.
- Rust worker by default: adds a toolchain without unique capability.

## Acceptance evidence

Crash and force-quit tests must establish child behavior, lease identity,
recovery actions, cancellation deadlines, and final output ownership.

## Revisit trigger

Accept one branch when product requirements decide whether work continues after
the UI process exits.
