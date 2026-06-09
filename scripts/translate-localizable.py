#!/usr/bin/env python3
"""Populate Resources/Localizable.xcstrings with LLM-drafted translations.

Translations live in scripts/translations.json:
    {"locales": [...], "strings": {key → locale → string}}
"locales" is the single source of truth for the supported-locale list
(check_localizations.py and release.sh read it too). The strings were
drafted by an LLM and need a native-speaker pass before public release.
Re-run this script after editing any value to apply changes to the
catalog.

The script is idempotent and additive: it sets `state` to `translated`
for any (key, locale) pair present here. Anything you've manually edited
in the catalog with `state: "needs_review"` or `state: "reviewed"` will
NOT be overwritten unless you change it back to `new`.

Usage:
    python3 scripts/translate-localizable.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "Resources" / "Localizable.xcstrings"
TRANSLATIONS_FILE = Path(__file__).resolve().parent / "translations.json"

def load_translations() -> tuple[list[str], dict[str, dict[str, str]]]:
    if not TRANSLATIONS_FILE.exists():
        sys.exit(f"missing translations file: {TRANSLATIONS_FILE}")
    data = json.loads(TRANSLATIONS_FILE.read_text())
    return data["locales"], data["strings"]


def main() -> None:
    if not CATALOG.exists():
        sys.exit(f"missing catalog: {CATALOG}")

    LOCALES, translations_by_key = load_translations()
    catalog = json.loads(CATALOG.read_text())
    strings = catalog.setdefault("strings", {})

    applied = 0
    skipped = 0
    unknown_keys = []

    for key, translations in translations_by_key.items():
        if key not in strings:
            unknown_keys.append(key)
            continue

        entry = strings[key]
        localizations = entry.setdefault("localizations", {})

        for locale in LOCALES:
            value = translations.get(locale)
            if value is None:
                continue

            existing = localizations.get(locale, {}).get("stringUnit", {})
            existing_state = existing.get("state", "new")

            # Preserve manual edits — only overwrite "new" / missing entries.
            if existing_state in ("translated", "needs_review", "reviewed", "stale") \
                    and existing.get("value") not in (None, ""):
                if existing.get("value") != value:
                    skipped += 1
                continue

            localizations[locale] = {
                "stringUnit": {"state": "translated", "value": value},
            }
            applied += 1

    if unknown_keys:
        print("warning: keys present in translations.json but missing from catalog:")
        for k in unknown_keys:
            print(f"  - {k!r}")

    CATALOG.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")
    print(f"Applied {applied} translation(s); skipped {skipped} manual edit(s).")


if __name__ == "__main__":
    main()
