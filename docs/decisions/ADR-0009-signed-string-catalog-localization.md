# ADR-0009: Signed String Catalog localization

- Status: Accepted
- Date: 2026-07-27

## Context

Independent `.strings` files drifted: Chinese approached full coverage while
Italian silently fell back for more than half of the UI. The independent fork
Bundle ID also meant an old macOS per-app language preference did not migrate,
and QuickRecorder offered no in-app explanation or selector.

## Decision

Use one English-source String Catalog for UI strings and embed every complete
shipping localization before signing. A bundled manifest is the release
locale contract. `AppLanguageStore` persists `system` or a canonical BCP-47
identifier, intersects the manifest with embedded localization bundles, feeds
SwiftUI's locale environment, and supplies the bundle used by legacy
`String.local` lookups.

Language changes update surfaces that observe those mechanisms. Settings asks
the user to restart for consistent menus, alerts, system-owned UI, and existing
windows. XLIFF is the translator interchange; Weblate may coordinate XLIFF
outside the application.

## Consequences

Every shipping locale must translate every catalog key with matching printf
placeholders before CI passes. Localizations remain deterministic signed
resources, and the app neither mutates macOS global language settings nor
loads unsigned runtime text. Native review and UI smoke remain necessary
because structural validation cannot judge prose or layout.

## Rejected alternatives

- Independent `.strings` tables allow silent drift.
- Writing `AppleLanguages` relies on an undocumented preference contract.
- Runtime downloads or translation frameworks weaken offline behavior and the
  signed-resource boundary.
- Listing incomplete languages misrepresents product support.

Revisit only if Apple adds a supported per-app language setter or a concrete
requirement emerges for independently signed, versioned offline resource packs.
