# Building And Signing

## Requirements

- macOS 12.3 or later
- Xcode with Swift 5 support
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

An alpha release may provide a self-signed, unnotarized DMG for explicit
testing. The release notes must identify that status, give a checksum, and
state any omitted or architecture-limited optional runtime. It must not be
presented as a generally supported installer.

A public installer requires all of the following:

1. a Bundle ID owned by this project;
2. Developer ID Application signing;
3. Apple notarization and stapling;
4. a reproducible universal app and runtime build;
5. a fork-owned update-signing key and feed;
6. published third-party notices and corresponding-source obligations.

Private keys, certificates, provisioning profiles, local paths, and machine
identifiers must never be committed.
