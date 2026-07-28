#!/usr/bin/env python3
"""Validate QuickRecorder's signed String Catalog localization contract."""

from __future__ import annotations

import argparse
import ast
import copy
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "QuickRecorder" / "Localizable.xcstrings"
MANIFEST_PATH = ROOT / "Localization" / "supported-locales.json"
SOURCE_ROOT = ROOT / "QuickRecorder"

SWIFT_LITERAL = r'"((?:[^"\\]|\\.)*)"'
LOCAL_LITERAL = re.compile(SWIFT_LITERAL + r"\.local\b")
UI_CONSTRUCTOR = re.compile(
    r"\b(?:Text|TextField|Button|Toggle|Label|Picker|SButton|SField|SGroupBox|"
    r"SInfoButton|SItem|SPicker|SSlider|SSteper|SToggle)\s*\("
)
UI_LABELED_LITERAL = re.compile(
    r"\b(?:label|tips|buttonTitle|placeholder)\s*:\s*" + SWIFT_LITERAL,
    re.DOTALL,
)
UI_HELP_LITERAL = re.compile(r"\.help\s*\(\s*" + SWIFT_LITERAL, re.DOTALL)
PRINTF = re.compile(
    r"%(?!%)(?:(?P<position>\d+)\$)?[-+#0']*"
    r"(?:\*|\d+)?(?:\.(?:\*|\d+))?(?:hh|h|ll|l|L|z|j|t|q)?"
    r"(?P<conversion>[@diuoxXfFeEgGaAcCsSp])"
)


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read {path.relative_to(ROOT)}: {error}") from error


def decode_swift_literal(raw: str, path: Path) -> str:
    try:
        return ast.literal_eval(f'"{raw}"')
    except (SyntaxError, ValueError) as error:
        raise ValueError(f"cannot parse string literal in {path.relative_to(ROOT)}: {error}") from error


def swift_code_without_comments(text: str) -> str:
    """Remove Swift comments while preserving strings and character positions."""
    result = list(text)
    index = 0
    in_string = False
    escaped = False
    block_depth = 0
    while index < len(text):
        if block_depth:
            if text.startswith("/*", index):
                result[index:index + 2] = "  "
                block_depth += 1
                index += 2
            elif text.startswith("*/", index):
                result[index:index + 2] = "  "
                block_depth -= 1
                index += 2
            else:
                if result[index] != "\n":
                    result[index] = " "
                index += 1
            continue
        if in_string:
            if escaped:
                escaped = False
            elif text[index] == "\\":
                escaped = True
            elif text[index] == '"':
                in_string = False
            index += 1
            continue
        if text[index] == '"':
            in_string = True
            index += 1
        elif text.startswith("//", index):
            end = text.find("\n", index)
            end = len(text) if end == -1 else end
            result[index:end] = " " * (end - index)
            index = end
        elif text.startswith("/*", index):
            result[index:index + 2] = "  "
            block_depth = 1
            index += 2
        else:
            index += 1
    return "".join(result)


def call_arguments(code: str, opening_parenthesis: int) -> str | None:
    depth = 0
    in_string = False
    escaped = False
    for index in range(opening_parenthesis, len(code)):
        character = code[index]
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
        elif character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth == 0:
                return code[opening_parenthesis + 1:index]
    return None


def is_user_facing_literal(raw: str) -> bool:
    if r"\(" in raw:
        return False
    value = ast.literal_eval(f'"{raw}"')
    return bool(value.strip()) and any(character.isalpha() for character in value)


def source_local_keys() -> set[str]:
    keys: set[str] = set()
    for path in sorted(SOURCE_ROOT.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for match in LOCAL_LITERAL.finditer(text):
            keys.add(decode_swift_literal(match.group(1), path))
    return keys


def source_swiftui_keys() -> set[str]:
    """Find static user-facing literals passed through project UI localization APIs.

    Constructor scoping excludes API/logging labels such as DispatchQueue(label:).
    Empty strings, pure symbols/numbers, and interpolated strings are excluded;
    interpolated LocalizedStringKey extraction remains Xcode's responsibility.
    """
    keys: set[str] = set()
    for path in sorted(SOURCE_ROOT.rglob("*.swift")):
        code = swift_code_without_comments(path.read_text(encoding="utf-8"))
        for match in UI_CONSTRUCTOR.finditer(code):
            arguments = call_arguments(code, match.end() - 1)
            if arguments is None:
                raise ValueError(f"unterminated UI constructor in {path.relative_to(ROOT)}")
            first = re.match(r"\s*" + SWIFT_LITERAL, arguments, re.DOTALL)
            candidates = ([first.group(1)] if first else []) + [
                labeled.group(1) for labeled in UI_LABELED_LITERAL.finditer(arguments)
            ]
            for raw in candidates:
                if is_user_facing_literal(raw):
                    keys.add(decode_swift_literal(raw, path))
        for match in UI_HELP_LITERAL.finditer(code):
            raw = match.group(1)
            if is_user_facing_literal(raw):
                keys.add(decode_swift_literal(raw, path))
    return keys


def placeholder_signature(value: str) -> list[tuple[str, str]]:
    signature: list[tuple[str, str]] = []
    sequence = 1
    for match in PRINTF.finditer(value):
        position = match.group("position") or str(sequence)
        signature.append((position, match.group("conversion")))
        sequence += 1
    return sorted(signature)


def validate(catalog: dict, manifest: dict, local_keys: set[str]) -> list[str]:
    errors: list[str] = []
    source_language = catalog.get("sourceLanguage")
    if source_language != manifest.get("sourceLanguage"):
        errors.append("locale-set: catalog and manifest sourceLanguage differ")

    entries = manifest.get("locales")
    if not isinstance(entries, list):
        return errors + ["manifest: locales must be an array"]

    identifiers = [entry.get("identifier") for entry in entries if isinstance(entry, dict)]
    if len(identifiers) != len(entries) or any(not isinstance(value, str) or not value for value in identifiers):
        errors.append("manifest: every locale needs a non-empty identifier")
    if len(set(identifiers)) != len(identifiers):
        errors.append("manifest: locale identifiers must be unique")
    incomplete = [entry.get("identifier") for entry in entries if not entry.get("complete")]
    if incomplete:
        errors.append(f"manifest: shipping locales are not complete: {', '.join(incomplete)}")

    strings = catalog.get("strings")
    if not isinstance(strings, dict) or not strings:
        return errors + ["catalog: strings must be a non-empty object"]

    catalog_locales = {source_language} if isinstance(source_language, str) else set()
    for item in strings.values():
        if isinstance(item, dict):
            localizations = item.get("localizations", {})
            if isinstance(localizations, dict):
                catalog_locales.update(localizations)
    manifest_locales = set(identifiers)
    if catalog_locales != manifest_locales:
        missing = sorted(manifest_locales - catalog_locales)
        extra = sorted(catalog_locales - manifest_locales)
        errors.append(f"locale-set: mismatch (missing={missing}, extra={extra})")

    for key in sorted(strings):
        item = strings[key]
        if not isinstance(item, dict):
            errors.append(f"catalog: {key!r} is not an object")
            continue
        if item.get("extractionState") == "stale":
            errors.append(f"stale: {key!r}")
        localizations = item.get("localizations", {})
        if not isinstance(localizations, dict):
            errors.append(f"catalog: {key!r} localizations is not an object")
            continue
        expected_signature = placeholder_signature(key)
        for locale in sorted(manifest_locales):
            localization = localizations.get(locale)
            unit = localization.get("stringUnit") if isinstance(localization, dict) else None
            if not isinstance(unit, dict):
                errors.append(f"missing: {locale} translation for {key!r}")
                continue
            if unit.get("state") != "translated":
                errors.append(f"state: {locale} translation for {key!r} is {unit.get('state')!r}")
            value = unit.get("value")
            if not isinstance(value, str) or not value:
                errors.append(f"missing: {locale} value for {key!r}")
                continue
            actual_signature = placeholder_signature(value)
            if actual_signature != expected_signature:
                errors.append(
                    f"placeholder: {locale} {key!r} expected {expected_signature}, got {actual_signature}"
                )

    absent = sorted(local_keys - set(strings))
    for key in absent:
        errors.append(f"source-key: literal .local key absent from catalog: {key!r}")
    return errors


def run_self_test(catalog: dict, manifest: dict, local_keys: set[str]) -> list[str]:
    failures: list[str] = []
    if validate(catalog, manifest, local_keys):
        return ["self-test: repository baseline must pass before mutation tests"]

    first_key = sorted(catalog["strings"])[0]
    translated_locale = next(
        entry["identifier"] for entry in manifest["locales"] if entry["identifier"] != catalog["sourceLanguage"]
    )
    cases: list[tuple[str, dict, dict, set[str], str]] = []

    changed = copy.deepcopy(catalog)
    del changed["strings"][first_key]["localizations"][translated_locale]
    cases.append(("missing", changed, manifest, local_keys, "missing:"))

    changed = copy.deepcopy(catalog)
    changed["strings"][first_key]["localizations"][translated_locale]["stringUnit"]["state"] = "new"
    cases.append(("state", changed, manifest, local_keys, "state:"))

    changed = copy.deepcopy(catalog)
    placeholder_key = next(key for key in sorted(changed["strings"]) if placeholder_signature(key))
    changed["strings"][placeholder_key]["localizations"][translated_locale]["stringUnit"]["value"] = "placeholder removed"
    cases.append(("placeholder", changed, manifest, local_keys, "placeholder:"))

    changed_manifest = copy.deepcopy(manifest)
    changed_manifest["locales"].append({"identifier": "test", "complete": True})
    cases.append(("locale-set", catalog, changed_manifest, local_keys, "locale-set:"))
    cases.append(("swiftui-source-key", catalog, manifest, local_keys | {"__missing_swiftui_fixture__"}, "source-key:"))

    for name, test_catalog, test_manifest, test_keys, marker in cases:
        if not any(error.startswith(marker) for error in validate(test_catalog, test_manifest, test_keys)):
            failures.append(f"self-test: {name} mutation was not rejected")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true", help="run deterministic negative mutation coverage")
    args = parser.parse_args()
    try:
        catalog = load_json(CATALOG_PATH)
        manifest = load_json(MANIFEST_PATH)
        local_keys = source_local_keys()
        swiftui_keys = source_swiftui_keys()
        keys = local_keys | swiftui_keys
    except ValueError as error:
        print(f"localization validation failed:\n- {error}", file=sys.stderr)
        return 1

    errors = validate(catalog, manifest, keys)
    if not errors and args.self_test:
        errors = run_self_test(catalog, manifest, keys)
    if errors:
        print("localization validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(
        f"Localization validation passed: {len(catalog['strings'])} keys, "
        f"{len(manifest['locales'])} shipping locales, {len(local_keys)} literal .local keys, "
        f"{len(swiftui_keys)} static SwiftUI keys."
    )
    pending_review = [
        entry["identifier"] for entry in manifest["locales"]
        if entry.get("reviewStatus") == "pending-native-review"
    ]
    if pending_review:
        print(f"Native-language review pending before release sign-off: {', '.join(pending_review)}.")
    if args.self_test:
        print("Localization validator self-test passed: 5 invalid mutations rejected.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
