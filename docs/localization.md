# Localization

`QuickRecorder/Localizable.xcstrings` is the source of truth for application UI
text. English is the source language. The shipping contract in
`Localization/supported-locales.json` currently declares English, Simplified
Chinese, Traditional Chinese, and Italian; a declared locale must be complete
and embedded before the application exposes it.

## Change a user-facing string

Add or update the English key in the String Catalog, translate it for every
shipping locale, preserve printf placeholders and newlines, then run:

```sh
python3 Scripts/check-localizations.py --self-test
```

The gate rejects locale-set drift, missing or non-translated units, stale
entries, placeholder mismatches, and catalog omissions for both literal
`.local` lookups and static SwiftUI/project-control localization keys.
Automated completeness does not replace native-language copy review or UI
layout testing; the completed Italian expansion still requires that review
before release sign-off.

## Translator exchange

Use Xcode's standard XLIFF boundary rather than editing a built application:

```sh
xcodebuild -exportLocalizations -project QuickRecorder.xcodeproj \
  -localizationPath /path/to/export
xcodebuild -importLocalizations -project QuickRecorder.xcodeproj \
  -localizationPath /path/to/reviewed-language.xcloc
```

Review the catalog diff after import and run the localization gate. Weblate may
manage reviewed XLIFF collaboration, but it is optional contributor
infrastructure: it is not linked to the app and never supplies runtime strings.

## Add a language

Translate the entire catalog, review it with a fluent speaker, compile it with
`xcstringstool`, and smoke-test the language in a signed Release build. Add its
canonical BCP-47 identifier to the manifest only after those gates pass. The
first right-to-left language additionally needs layout, text direction,
keyboard navigation, and accessibility review. Never advertise an incomplete
or unreviewed future language as supported.

Localizations are sealed into the signed bundle. Do not download packs, modify
an installed app, write the undocumented `AppleLanguages` preference, or send
recording/user content to a translation service.
