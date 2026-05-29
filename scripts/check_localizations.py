#!/usr/bin/env python3
"""Fail if any user-facing string is missing a translation for a supported locale.

Run in CI (.github/workflows/localizations.yml) and locally:

    python3 scripts/check_localizations.py

A string is considered translated for a locale when it has a non-empty
`stringUnit` value in one of OK_STATES. The empty-key artifact Xcode emits
and any entry explicitly marked `shouldTranslate: false` are skipped. The
source language (en) is not checked — the catalog key *is* its value.

To fix a reported gap: add the string to scripts/translate-localizable.py
and run it, or set `"shouldTranslate": false` on the entry if it genuinely
shouldn't be localized (brand names, symbols, etc.).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "Resources" / "Localizable.xcstrings"

# Keep in sync with LOCALES in scripts/translate-localizable.py.
TARGET_LOCALES = [
    "en-GB", "de", "es", "es-419", "fr", "it", "pt-BR",
    "ja", "zh-Hans", "zh-Hant", "ko",
    "hi", "ru", "pl", "nl",
    "ar", "fa", "he",
]

# Present + current. "new" = never translated; "stale" = source changed since.
OK_STATES = {"translated", "reviewed", "needs_review"}


def main() -> int:
    if not CATALOG.exists():
        sys.exit(f"missing catalog: {CATALOG}")

    catalog = json.loads(CATALOG.read_text())
    strings = catalog.get("strings", {})

    gaps: dict[str, list[str]] = {}
    for key, entry in strings.items():
        if key == "":
            continue
        if entry.get("shouldTranslate") is False:
            continue
        localizations = entry.get("localizations", {})
        missing = [
            loc for loc in TARGET_LOCALES
            if localizations.get(loc, {}).get("stringUnit", {}).get("state") not in OK_STATES
            or not localizations.get(loc, {}).get("stringUnit", {}).get("value")
        ]
        if missing:
            gaps[key] = missing

    if gaps:
        print(f"❌ {len(gaps)} string(s) missing translations:\n")
        for key, missing in gaps.items():
            preview = key if len(key) <= 60 else key[:57] + "…"
            print(f"  • {preview!r}")
            print(f"      missing ({len(missing)}): {', '.join(missing)}")
        print("\nAdd them to scripts/translate-localizable.py and run it, or set")
        print('"shouldTranslate": false on the entry if it shouldn\'t be localized.')
        return 1

    checked = sum(1 for k in strings if k != "")
    print(f"✓ all {checked} strings translated for {len(TARGET_LOCALES)} locales")
    return 0


if __name__ == "__main__":
    sys.exit(main())
