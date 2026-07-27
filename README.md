# QuickRecorder Enhanced

Lecture-first screen recording for macOS, with cleaner microphone audio and
smaller validated archives.

[简体中文](README.zh-CN.md) · [Documentation](docs/README.md) ·
[Releases](https://github.com/Nongfsq/QuickRecorder-Enhanced/releases) ·
[Upstream project](https://github.com/lihaoyun6/QuickRecorder)

![macOS 12.3+](https://img.shields.io/badge/macOS-12.3%2B-111111?logo=apple)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)
![Release](https://img.shields.io/github/v/release/Nongfsq/QuickRecorder-Enhanced?include_prereleases)
![License](https://img.shields.io/badge/license-AGPL--3.0-663399)

> QuickRecorder Enhanced is an independent continuation of
> [QuickRecorder](https://github.com/lihaoyun6/QuickRecorder) by
> [lihaoyun6](https://github.com/lihaoyun6). It is not an official upstream
> release.

## What is different

- **Microphone noise reduction:** one tested RNNoise speech-cleanup option at
  48 kHz mono, using an 80% processed and 20% original mix.
- **Lecture capture:** practical presets for readable text, lower frame rates,
  adaptive VFR, mono audio, and long recordings.
- **AV1 archive workflow:** post-record compression with FFmpeg/SVT-AV1,
  progress reporting, manifests, and timestamp validation.
- **Safer audio export:** correct mono QMA rendering and explicit failures
  instead of silently producing an empty output.
- **Predictable permissions:** ScreenCaptureKit startup failures do not trigger
  an automatic permission-request loop.

RNNoise is applied only to microphone audio. Captured system audio is not sent
through the noise-reduction pipeline.

## Status

The current `v1.7.0-alpha.2` release includes an **experimental Universal
DMG**. It uses the project's stable self-signing identity, but it is not
Developer ID signed or Apple-notarized. macOS may require **Open** from the
Finder context menu on first launch.

The optional bundled FFmpeg runtime is omitted from this Alpha installer until
its Universal packaging and notices are release-ready. AV1 archive jobs require
a separately installed compatible FFmpeg in the meantime.

The project now has its own version line and release page. The legacy upstream
Sparkle feed is disabled; future binary updates will use a fork-owned signing
key and update feed.

## Build

Open `QuickRecorder.xcodeproj` in Xcode on macOS 12.3 or later. Select your own
development team and use a Bundle ID you control before running the app.

macOS privacy permissions depend on both the Bundle ID and code signature. A
new identity will correctly require one new Screen Recording and Microphone
authorization. See [Building and signing](docs/building.md).

## Documentation

- [Feature guide](docs/features.md)
- [Building and signing](docs/building.md)
- [Release policy](docs/releases.md)
- [Upstream relationship](docs/upstream.md)
- [Archive command-line tools](Tools/Archive/README.md)

## Releases

Fork releases start at `v1.7.0-alpha.1`. Upstream tags and release artifacts
are not republished as releases of this project.

Every published release includes a DMG; a release whose DMG is not ready stays
in Draft. Alpha DMGs may be explicitly labeled as self-signed and unnotarized
for hands-on testing. A generally supported installer still requires Developer
ID signing, notarization, complete runtime notices, and a fork-owned update key.

## License and attribution

QuickRecorder Enhanced is distributed under the
[GNU Affero General Public License v3.0](LICENSE). The original QuickRecorder
project and author remain credited in [NOTICE.md](NOTICE.md). Third-party
components retain their own license notices in their source packages.
