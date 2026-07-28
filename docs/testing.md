# Testing Strategy

QuickRecorder uses a risk-based validation pyramid. Pure logic should be moved
behind package APIs so it can be tested without launching or replacing the
macOS application.

## Routine gate

Every change should run:

```sh
sh Scripts/check-public-tree.sh
swift test --package-path Packages/RNNoiseProcessor
swift test --package-path Packages/ArchiveJobCore
swift test --package-path Packages/RecordingDomain
swift test --package-path Packages/WindowPlacementCore
plutil -lint QuickRecorder/Info.plist
plutil -lint QuickRecorder/QuickRecorder.entitlements
python3 Scripts/check-localizations.py --self-test
```

When a package is not yet present on a historical branch, omit only that
package's command. Before a public commit, inspect the staged diff as well as
the working tree; the public-tree script scans both content views so partially
staged local paths or credentials cannot bypass the gate.

## Media contract gate

Use synthetic, non-private fixtures to verify:

- packet timestamp monotonicity and audio/video synchronization;
- pause and resume timeline behavior;
- stop while sample callbacks are active;
- RNNoise partial-frame flush and timestamp continuity;
- failed or cancelled remux preserves a recoverable source;
- archive validation, decode smoke, duration tolerance, and recovery policy;
- QMA unequal-track duration and sample-rate behavior.

Generated media, logs, manifests, result bundles, and machine paths are local
artifacts and must not be committed.

## Application integration gate

The application gate is intentionally separate from routine package testing.
It requires an explicitly authorized signed Universal Release build and static
bundle inspection. Human-run validation of the installed production app then
covers permissions, capture routes, pause/resume, finalization, archive quit
behavior, recovery, and upgrade behavior.

Do not use a Debug application build as a substitute for this gate. Do not
reset TCC to automate it.

For localization changes, also compile `QuickRecorder/Localizable.xcstrings`
with `xcstringstool` and confirm that the Release bundle contains `en`,
`zh-Hans`, `zh-Hant`, and `it` localizations. Switching every language,
checking long settings labels, and confirming persistence after restart remain
human-run application smoke tests.

## Public release gate

A public binary additionally requires Developer ID signing, notarization and
stapling, universal app and runtime slices, dependency and license inventory,
clean-install and upgrade evidence, expanded-artifact privacy scanning,
checksums, and a fork-owned update feed and key.
