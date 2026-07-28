# Global Localization PLAN + TASK

## Summary

Migrate QuickRecorder to a signed, catalog-based localization system; add an app-language setting; complete every currently shipped language; enforce translation completeness for future user-visible changes; and preserve an XLIFF boundary for open-source translation collaboration.

## Current reality

The app has English fallback plus `zh-Hans`, `zh-Hant`, and incomplete `it` `.strings` files. Runtime selection is implicit and tied to macOS/Bundle ID. Public CI lints only two language files. No application test target exists.

## Architecture decisions

- `Localizable.xcstrings` is the only runtime UI string source.
- `AppLanguageStore` is the only app-owned language preference owner.
- `Localization/supported-locales.json` declares release languages.
- Runtime-downloaded language packs and undocumented `AppleLanguages` writes are prohibited.
- XLIFF is the translator/service interchange; Weblate is optional infrastructure, not an app dependency.

## Frontend workstream

General Settings receives a native application-language picker and restart guidance. Every app scene receives the selected locale. Existing `String.local` lookups use the selected localization bundle.

## Backend/API/data workstream

N/A — no backend. Local persistence adds one canonical locale identifier in UserDefaults.

## Analytics/observability/security considerations

No remote analytics. Embedded translations are sealed by the app signature. Diagnostics must not log translated user content. External translation exchange contains public source strings only.

## Migration order

Catalog and validator first; semantic parity and Italian completion second; project resource switch third; runtime selector fourth; CI/docs/rules fifth; Release validation last.

## Rollout, compatibility, and rollback notes

System Default preserves normal macOS behavior. The old tables and new catalog do not coexist in the final target. Rollback restores the old PBX variant group and removes the selector/store; the saved preference is ignored safely.

## Test and QA plan

- Validate catalog JSON, release locale set, translation presence/state, and placeholder parity.
- Compare migrated Chinese/Italian values with their prior source tables.
- Parse/compile Swift and build the signed Universal Release.
- Inspect compiled `.lproj` resources and strict signature.
- Defer visual switching/restart smoke to the user-approved post-install test.

### I18N-001: Create catalog and locale contract

- Status: Complete (374 catalog keys across four embedded locales).

- Depends on: none
- Files: `QuickRecorder/Localizable.xcstrings`, `Localization/supported-locales.json`
- Change: migrate every current UI key and translation into an English-source String Catalog; declare `en`, `zh-Hans`, `zh-Hant`, and `it` as release locales.
- Acceptance: Chinese values are semantically identical to prior tables; no current key is lost; catalog compiles.
- Validation: catalog validator and `xcrun xcstringstool compile` in a temporary directory.

### I18N-002: Complete Italian and translation metadata

- Status: Engineering complete; fluent Italian review remains a Release sign-off gate.

- Depends on: I18N-001
- Files: `QuickRecorder/Localizable.xcstrings`
- Change: translate every required English source key missing from Italian; preserve format placeholders; mark translations complete.
- Acceptance: Italian required-key coverage is 100%; placeholder parity is exact.
- Validation: `python3 Scripts/check-localizations.py` plus manual review list exported from the catalog.

### I18N-003: Add language preference owner

- Status: Complete, including all 15 standalone `NSHostingView` roots.

- Depends on: I18N-001
- Files: `QuickRecorder/Localization/AppLanguageStore.swift`, `QuickRecorder/QuickRecorderApp.swift`
- Change: discover complete embedded locales, store `system` or a canonical identifier, expose selected locale/bundle, and inject locale into every SwiftUI scene.
- Acceptance: System Default follows Bundle preference; supported overrides resolve an embedded localization; invalid/removed IDs fall back safely.
- Validation: Swift parse/build and a standalone normalization fixture or equivalent focused check.

### I18N-004: Route legacy and Settings UI through localization owner

- Status: Complete; the installed build was observed in English, Simplified Chinese, Traditional Chinese, and Italian.

- Depends on: I18N-003
- Files: `QuickRecorder/ViewModel/SettingsView.swift`, `QuickRecorder/QuickRecorderApp.swift`, `QuickRecorder/Localizable.xcstrings`
- Change: add Application Language to General Settings; route `String.local` through the selected bundle; show restart guidance after a change.
- Acceptance: menu lists System Default plus every release locale using native names; choice persists; no unsupported locale is offered.
- Validation: source audit, Swift build, and post-install user smoke.

### I18N-005: Switch the Xcode resource graph

- Status: Complete; compiled catalog output was validated in the signed Universal app and mounted DMG.

- Depends on: I18N-001, I18N-002
- Files: `QuickRecorder.xcodeproj/project.pbxproj`, prior `*.lproj/Localizable.strings`
- Change: replace the localized `.strings` variant group with `Localizable.xcstrings`; retain localized Credits and InfoPlist resources.
- Acceptance: build contains compiled catalogs for every release locale and no duplicate `Localizable.strings` source.
- Validation: `xcodebuild` plus built-bundle resource inventory.

### I18N-006: Add deterministic localization gate

- Status: Complete; the gate covers catalog structure, placeholders, 109 literal `.local` keys, and 196 static SwiftUI keys.

- Depends on: I18N-001
- Files: `Scripts/check-localizations.py`, `.github/workflows/public-safety.yml`, `docs/testing.md`
- Change: fail on malformed catalog, missing release locale, missing/stale translation, source-key drift, or format-placeholder mismatch.
- Acceptance: valid repository passes; controlled invalid fixtures/check modes fail with actionable messages.
- Validation: `python3 Scripts/check-localizations.py` and CI YAML review.

### I18N-007: Document translator and new-language workflow

- Status: Complete, including the local excluded `AGENTS.md` invariant.

- Depends on: I18N-001, I18N-006
- Files: `docs/localization.md`, `docs/README.md`, `docs/features.md`, local `AGENTS.md`
- Change: document Xcode/XLIFF export/import, optional Weblate integration, locale promotion gate, RTL gate, and the invariant that every new user-facing feature updates every release locale.
- Acceptance: a new contributor can add a key or locale without inventing process; private agent instructions remain untracked.
- Validation: link check, public-tree check, and instruction-chain review.

### I18N-008: Record durable architecture decision

- Status: Complete.

- Depends on: I18N-001 through I18N-007
- Files: `docs/decisions/ADR-0009-signed-string-catalog-localization.md`, `docs/decisions/README.md`
- Change: accept the embedded String Catalog/app-owned-selection architecture and its rejected alternatives/revisit triggers.
- Acceptance: decision and implementation agree.
- Validation: documentation review and link check.

### I18N-009: Run Release gate

- Status: Complete. Catalog compilation, source parsing/typechecking, public-tree safety, 43 package tests, signed Universal Release build, bundle inventory, strict signature/Gatekeeper validation, direct installation, mounted-DMG inspection, and multilingual UI smoke pass.

- Depends on: I18N-001 through I18N-008
- Files: no production files beyond fixes required by failed validation
- Change: run localization, public-tree, package, source, signed Universal Release, bundle-inventory, and signature checks without launching or installing a new app.
- Acceptance: all automated/static gates pass; remaining user-run switching smoke is explicit.
- Validation: commands recorded in closeout.

## Handoff

- Assumptions: English development language; System Default initially selected; restart guidance is acceptable for full consistency; only complete locales ship.
- Non-goals: runtime downloads, automatic cloud translation, global language/TCC mutation, Weblate deployment, or automatic app launch.
- Rollback: restore `.strings` resource graph and remove the store/settings entry; no recording data or media schema is touched.
- Status: engineering complete and installed as 1.7.0 build 173. Public Release sign-off still requires fluent Italian copy review; that review does not block the Stage 0 engineering checkpoint.
