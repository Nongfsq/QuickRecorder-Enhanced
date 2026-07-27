# Release Policy

QuickRecorder Enhanced uses its own release line beginning with
`v1.7.0-alpha.1`. Upstream tags are historical upstream versions, not releases
of this project, and are not copied into this repository.

## Current phase

Alpha releases provide a stable review point for the fork's code and
documentation. Every published Release must carry a DMG; if the DMG is not
ready, the Release remains a Draft. An Alpha may carry an experimental DMG when
its signing, notarization, architecture, and bundled-runtime limitations are
stated in the release notes. Such a DMG is for hands-on testing and is not a
generally supported installer.

## Binary release gate

The first binary release must pass the signing, notarization, architecture,
runtime-license, clean-install, upgrade, and privacy-permission requirements in
[building.md](building.md).

The updater remains disabled until the project publishes its own appcast and
Sparkle public key. It must never consume the upstream QuickRecorder update
feed.

## Versioning

- tags: `vMAJOR.MINOR.PATCH` with optional prerelease suffix;
- app version: numeric `MAJOR.MINOR.PATCH`;
- release assets: generated only by the fork's release process;
- release notes: describe fork changes and credit the upstream base once.
