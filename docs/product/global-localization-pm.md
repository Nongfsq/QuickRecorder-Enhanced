# Global Localization Product Requirements

Date: 2026-07-27

## Problem and product intent

QuickRecorder currently contains several translations but gives users no in-app explanation or control, and a Bundle ID migration made a previously selected language appear lost. The product must treat language as a first-class preference and translations as part of feature completeness.

## Target users and jobs

- Multilingual users choose QuickRecorder's language without changing the rest of macOS.
- Translators receive stable keys, context, placeholders, plural rules, and reviewable deltas.
- Contributors cannot merge a user-visible feature that silently falls back to English in a shipping locale.
- Maintainers add a locale through a documented, reversible workflow rather than source-code surgery.

## Jobs-caliber PM judgment

- Essential promise: every language shown in QuickRecorder is complete enough to trust.
- Taste bar: the language picker uses native language names, System Default is obvious, and incomplete locales never appear as decorative options.
- Narrative: choose once, keep working; future upgrades preserve the choice.
- Rejected compromise: listing many empty or raw machine-translated languages. Reach without comprehension is not localization.
- Rejected compromise: sending UI strings to a runtime translation service. Recording must remain offline-capable and deterministic.

## Current reality

- English is the development/fallback language.
- Simplified and Traditional Chinese are nearly complete.
- Italian contains substantially fewer keys and often falls back to English.
- `.strings` files drift independently; CI lints only two of them.
- macOS recognized all embedded locales, but Settings had no language surface.

## Proposed behavior

- General Settings shows Application Language with System Default and every complete embedded locale.
- Selection is stored under the fork's Bundle ID and survives upgrades.
- SwiftUI content updates through the locale environment; legacy/AppKit lookup uses the selected bundle. A restart notice guarantees consistency for menus, system-owned UI, and document scenes.
- The initial catalog ships English, Simplified Chinese, Traditional Chinese, and completed Italian.
- New locales are translated through Xcode/XLIFF, reviewed, validated, then added to the shipping manifest and menu.

## Success criteria

- No existing Chinese translation is lost in migration.
- Italian reaches the same required-key set as the development language.
- Every shipping locale passes syntax, missing-key, stale-state, and placeholder validation.
- The signed Release bundle contains exactly the declared shipping locales plus Base resources.
- A contributor adding a visible key without all shipping translations fails the standard localization gate.
- User smoke confirms each language is selectable and persists after restart.

## Non-goals

- Automatically translating arbitrary user content.
- Shipping unreviewed locale placeholders.
- Downloading or modifying language resources after signing.
- Operating a Weblate server in this task.
- Claiming RTL readiness before Arabic/Hebrew layout and input testing exists.

## Risks and open questions

- Human review is still required for nuanced translations; automated validation proves completeness, not prose quality.
- The first RTL locale requires a separate layout/accessibility gate.
- System permission prompts may continue following the macOS per-app language until restart; this is documented rather than hidden.
