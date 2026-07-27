# ADR-0003: Archive Worker Boundary

Status: Accepted

## Context

Orderly termination can wait for or cancel an in-process FFmpeg job. A crash or
force quit may leave child-process ownership ambiguous. Continuing archives
after the UI exits requires a different lifecycle contract than orderly
wait-or-cancel behavior.

## Decision

QuickRecorder uses the **wait or cancel** contract for the current architecture:

- archive execution stays in-process;
- orderly application termination waits for completion or performs bounded
  cancellation;
- archive workers do not intentionally continue after the UI exits;
- crash and force-quit recovery may validate or restart durable jobs only after
  the prior process lifetime has ended.

Continuation after exit remains a future product decision. If it becomes a
requirement, use a separately signed Swift executable, XPC service, or helper
that exclusively owns process groups and renewable job leases. Do not use Rust
merely to create this boundary.

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

Revisit if users require archive work to continue after QuickRecorder quits, or
if measured cancellation/recovery reliability cannot meet the current contract.
