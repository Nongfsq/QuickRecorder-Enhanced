# Architecture Blueprint: Global Localization

## Summary

- Product goal: make QuickRecorder feel intentionally local in every language it claims to support, expose an in-app language choice, and make untranslated UI a release-blocking defect.
- Architecture type: existing-system localization refactor.
- Selected stack: Apple String Catalogs (`.xcstrings`) as the signed runtime source of truth; an app-owned language preference layered over macOS system default; Xcode XLIFF export/import for translators; optional Weblate collaboration outside the runtime.
- Primary constraints: macOS 12.3 deployment, SwiftUI/AppKit mix, signed Universal releases, current English-keyed `.strings`, no application test target, and an incomplete Italian catalog.
- Non-goals: runtime machine translation, modifying a signed `.app` after installation, silently presenting incomplete languages, or adding a cloud translation service to the application.

## Decisions

- Frontend/runtime: one `AppLanguageStore` exposes System Default plus every complete localization embedded in the signed bundle. Why: it gives users a discoverable in-app choice using public Foundation/SwiftUI mechanisms and automatically discovers future shipped languages. Rejected: only linking to System Settings (insufficient discoverability) and writing the undocumented `AppleLanguages` preference (unsupported contract). Revisit when: Apple publishes a supported API for setting the macOS per-app language directly.
- Localization source: migrate `Localizable.strings` to one `Localizable.xcstrings` catalog with English as the development language. Why: Xcode extracts keys, tracks stale/new translation state, handles plurals and variations, and is Apple's replacement for `.strings`/`.stringsdict`. Rejected: continuing independent `.strings` files (silent drift) and a third-party runtime framework (unnecessary dependency). Revisit when: Apple supersedes String Catalogs.
- Language scope: ship only locales that pass 100% required-key and placeholder validation; initial shipping set remains English, Simplified Chinese, Traditional Chinese, and completed Italian. Why: real support beats a long misleading menu. Rejected: adding empty machine-translated locales to inflate coverage. Revisit when: a new locale has a reviewed XLIFF and UI-layout smoke evidence.
- External workflow: use Xcode's standard XLIFF export/import boundary; document Weblate as the preferred open-source collaboration option but do not deploy or couple it in this change. Why: translators can work independently while the repository remains the authority. Rejected: proprietary service lock-in and downloaded runtime packs. Revisit when: translation volume justifies operating Weblate or a hosted service.
- Persistence: `quickRecorder.appLanguage` stores `system` or a canonical BCP-47 identifier; `AppLanguageStore` is the only writer. Why: independent fork identity and explicit user intent survive upgrades. Rejected: copying all legacy preferences or mutating global language order. Revisit when: a supported macOS API can own this state.
- Security: localizations are embedded before signing. Why: macOS code signatures seal resources. Rejected: writing `.lproj` content into the installed app or loading unsigned remote translations. Revisit when: independently signed resource bundles have a concrete offline-update requirement and version/integrity protocol.
- Testing: a repository validator checks catalog syntax, required locales, missing/stale translations, placeholder parity, and source-key discovery; Release validation checks compiled bundle localizations. Rejected: `plutil` checks for two languages only. Revisit when: an application test target can add localized snapshot/UI coverage.
- CI/CD and deploy: public-safety CI runs the localization validator; signed Release builds remain the final bundle gate. Rejected: translator changes bypassing CI. Revisit when: translation PR volume merits a dedicated workflow.
- Observability: no translated text, window titles, or locale-specific user data is logged. The selected canonical locale may be included only in user-triggered diagnostics. Rejected: remote language analytics. Revisit when: explicit privacy-reviewed telemetry exists.
- Documentation: `docs/localization.md` is the contributor workflow; the root private `AGENTS.md` holds the compact invariant that every user-facing change updates all shipping locales. Rejected: duplicating the full workflow in agent instructions. Revisit when: localization ownership changes.

## System Shape

- Runtime surfaces: app/document scenes, Settings, SwiftUI views, AppKit alerts/menus, notifications, and Info.plist purpose strings.
- Module boundaries: `AppLanguageStore` owns locale selection; SwiftUI receives its locale through the scene environment; legacy `String.local` delegates to the selected localization bundle; String Catalog owns translations; CI validator owns drift detection.
- Data flow: user selects locale → store persists canonical ID → SwiftUI locale and selected bundle update → views redraw; restart notice covers AppKit/system-owned surfaces that cannot reliably update live.
- External integrations: optional XLIFF exchange with translators or Weblate; no runtime network integration.
- Background jobs/events: none.

## Scaffold Plan

- `QuickRecorder/Localization/AppLanguageStore.swift`: supported-language discovery, preference normalization, bundle lookup, and observable locale state.
- `QuickRecorder/Localizable.xcstrings`: source and shipping translations.
- `Localization/supported-locales.json`: release locale contract and human-review metadata.
- `Scripts/check-localizations.py`: catalog/source/placeholder/coverage validation.
- `docs/localization.md`: translation and new-feature workflow.
- `docs/product/global-localization-pm.md`: user-facing promise and quality bar.
- `docs/plans/2026-07-27-global-localization-plan.md`: implementation ledger.
- Validation: `python3 Scripts/check-localizations.py`, `sh Scripts/check-public-tree.sh`, package tests, and a signed Universal Release build.

## Migration and Rollout

- Current state → target state: merge the three `.strings` tables into `Localizable.xcstrings`, preserve translated values, fill Italian gaps, replace the PBX variant group with the catalog, and add the language store/settings surface.
- Staged rollout: validate semantic parity before deleting old files; compile the catalog; inspect the built `.lproj` set; keep System Default as the initial preference unless a user chooses an override.
- Compatibility window: no runtime dual-source window; migration validation compares old tables to the catalog before old files are removed in the same change.
- Data migration: the new preference is additive. Existing macOS per-app language remains the System Default input; no global or TCC state is rewritten.
- Rollback: revert the language store and PBX catalog reference, restore prior `.strings` files, and remove the localization validator. User preference remains harmless if the feature is absent.
- Kill switch: selecting System Default bypasses the app override.
- Rollback signal: missing compiled locale, localization lookup returning keys for existing translated entries, placeholder validation failure, or signed-build failure.

## Implementation Sequence

- Foundation: create the source catalog and release-locale manifest; validate semantic parity and complete Italian.
- First vertical slice: route `String.local` and the Settings General language picker through `AppLanguageStore`; this exercises the riskiest mixed SwiftUI/AppKit lookup boundary.
- Hardening: attach locale environment to every scene, add restart guidance, CI validation, docs, and durable agent rule.
- Launch gates: catalog validation, source parse/build, signed Universal Release, compiled localization inventory, signature/public-tree checks, then user-run language switching smoke.

## Verification

- Unit/component tests: pure validator fixtures for missing locale, placeholder mismatch, stale state, and valid catalog; store normalization checked through a standalone Swift compile/run fixture if practical.
- API/contract tests: `supported-locales.json` and catalog locale set must match; every required key has every shipping translation.
- Integration/E2E tests: static bundle inspection in this turn; user-run Settings → language → restart verification afterward.
- Build/type/lint checks: localization validator, Swift frontend parse, affected package tests, full signed Universal Release build.
- Deployment smoke: verify compiled `en`, `zh-Hans`, `zh-Hant`, and `it` resources and strict code signature. Do not launch automatically.
- Observability checks: N/A — no new runtime logging or network integration.

## ADRs to Write

- ADR: Signed String Catalog localization with app-owned selection. Context/decision: embedded catalog is the runtime authority; XLIFF is the translator boundary; app selection uses public locale/bundle APIs. Rejected: downloaded packs, undocumented `AppleLanguages`, runtime translation frameworks. Revisit when: Apple adds a supported per-app language setter or independently updated signed packs become a product requirement.

## Risks And Assumptions

- Risks: SwiftUI and AppKit surfaces may refresh at different times; Italian translation quality needs human review; long strings can expose layout defects; plural/format strings need explicit variants; Info.plist/system dialogs follow macOS bundle selection rather than an app-only live override.
- Assumptions: correctness is more valuable than advertising many incomplete locales; user-visible language changes may require restart for full consistency; English remains the development language.
- Revisit triggers: a fifth locale reaches reviewed completeness; RTL language work begins; translation PR volume justifies Weblate deployment; Apple changes macOS app-language APIs.

## Handoff

- Assumptions with stated defaults: System Default is the initial choice; language changes update SwiftUI immediately but the UI requests restart for full consistency; new locales are hidden until complete.
- Open questions: none blocking. Weblate hosting is deferred with the default of repository-managed XLIFF exchange.
- Non-goals: runtime download, machine translation presented as final, TCC/global-language mutation, and UI launch during automated validation.
- Status: blueprint written and execution is authorized by the current request; implementation proceeds through the localization PLAN+TASK.
