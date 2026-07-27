# Building And Signing

## Requirements

- macOS 12.3 or later
- Xcode with Swift 5.9 package support or later
- an Apple Development identity for local execution

Open `QuickRecorder.xcodeproj`, choose a development team, and assign a Bundle
ID controlled by that team.

## Why identity matters

macOS privacy permissions are attached to the combination of Bundle ID and code
signature. Copies with the same visible name but different signatures are
different applications to TCC.

Use one stable identity for repeated local testing. Do not distribute ad-hoc
builds with another project's Bundle ID. Moving to QuickRecorder Enhanced's
independent identity will require one new permission grant, after which normal
updates signed by the same identity should retain authorization.

## Public binaries

Every published GitHub Release must include a DMG. If the DMG has not passed
the release checks, keep the Release in Draft instead of publishing a
source-only version.

An Alpha may use a project-specific self-signing identity and remain
unnotarized when the DMG, release notes, and checksum clearly identify it as an
experimental installer. It must use the fork-owned Bundle ID, contain a
Universal app, omit any architecture-limited optional runtime, and pass static
signature and mounted-image validation.

Do not present an installer as generally supported until all of the following
are complete:

1. a Bundle ID owned by this project;
2. Developer ID Application signing;
3. Apple notarization and stapling;
4. a reproducible universal app and runtime build;
5. a fork-owned update-signing key and feed;
6. published third-party notices and corresponding-source obligations.

Internal or local validation artifacts are not releases and must not be
uploaded or presented as installers.

Private keys, certificates, provisioning profiles, local paths, and machine
identifiers must never be committed.
