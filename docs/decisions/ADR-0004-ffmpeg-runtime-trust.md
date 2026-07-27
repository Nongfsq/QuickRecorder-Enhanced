# ADR-0004: FFmpeg Runtime Trust And Release Boundary

Status: Accepted

## Context

Archive processing executes native FFmpeg and FFprobe against user media. A
mutable managed runtime can be substituted after installation, and folder
resources can accidentally include ignored local binaries in a build.

## Decision

Production executes only a sealed bundled runtime or separately signed helper
whose identity, architectures, manifest, and digests are anchored in signed
release metadata and revalidated before launch. Developer/Homebrew fallback is
non-production only. Release inputs explicitly enumerate runtime resources and
fail closed on ignored executables or incomplete provenance.

## Rationale

Capability output does not establish binary identity. Native parsers inherit
the app's filesystem and process environment, so runtime trust is a security,
privacy, reproducibility, notarization, and license boundary.

## Rejected alternatives

- Trust any executable that reports expected codecs.
- Verify checksums only at installation time.
- Rely on Git ignore and tracked-tree scanning to define Release contents.

## Consequences

The release workflow needs pinned source recipes, universal slices, dylib
closure checks, nested signing, notices and corresponding-source obligations,
and expanded-artifact privacy scanning. Local development remains possible
through an explicitly enabled non-production path.

## Revisit trigger

Revisit the packaging mechanism if FFmpeg moves into a separately distributed
signed component or an App Sandbox-compatible helper, while preserving the
same fail-closed identity guarantees.
