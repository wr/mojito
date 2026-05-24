#!/usr/bin/env python3
"""
Build Mojito's bundled emoji database.

Combines emojibase compact dataset with iamcal (Slack-style) and emojibase
shortcodes into a single JSON optimized for fuzzy lookup. Output goes to
Resources/Emoji/emoji.json.

Run this whenever you want to refresh the dataset:
    python3 scripts/build_emoji_db.py

Security:
    The upstream JSON is fetched over HTTPS but pinned to specific SHA256
    digests in EXPECTED_SHA256 below. If the source changes (intentionally
    bumped or upstream-tampered), the script aborts and the maintainer must
    review the new content and update the digests by hand. This prevents a
    silently-malicious upstream from injecting crafted unicode sequences
    (homoglyphs, bidi overrides) into our shipped bundle.
"""

import hashlib
import json
import os
import sys
import urllib.request

REPO = "https://raw.githubusercontent.com/milesj/emojibase/master/packages/data/en"
SOURCES = {
    "compact":   f"{REPO}/compact.raw.json",
    "iamcal":    f"{REPO}/shortcodes/iamcal.raw.json",
    "emojibase": f"{REPO}/shortcodes/emojibase.raw.json",
    "github":    f"{REPO}/shortcodes/github.raw.json",
}

# Expected SHA256 digests of the upstream JSON files. To bump emojibase:
#   1. rm -rf .emoji-cache/
#   2. Manually inspect new files for malicious unicode sequences.
#   3. Run `shasum -a 256 .emoji-cache/*.json` and paste new digests below.
# If a fetched file doesn't match, the script aborts BEFORE writing emoji.json.
EXPECTED_SHA256 = {
    "compact":   "3a2bc2623881128a11c77ce78bd8c0af7951d2bce9a1adc75f697f6b45300e91",
    "iamcal":    "c8181b1dabee299b7991739dd634a943c36a67f278995e7b1e48dc7f69b7d073",
    "emojibase": "5ea367e3866688e733a990bb099c36ffdee43e08ba1c03d48001b6fecf746fbe",
    "github":    "279d7669438a0f810db53aa62a12dbd40285270ea0598222575e9540781e3dfb",
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources", "Emoji", "emoji.json")
CACHE = os.path.join(ROOT, ".emoji-cache")

os.makedirs(CACHE, exist_ok=True)


def fetch(name: str, url: str) -> object:
    cache_path = os.path.join(CACHE, f"{name}.json")
    if not os.path.exists(cache_path):
        print(f"  fetching {name}…")
        with urllib.request.urlopen(url) as r:
            data = r.read()
        with open(cache_path, "wb") as f:
            f.write(data)

    with open(cache_path, "rb") as f:
        raw = f.read()

    actual = hashlib.sha256(raw).hexdigest()
    expected = EXPECTED_SHA256.get(name)
    if expected is None:
        raise SystemExit(
            f"error: no expected SHA256 pinned for source '{name}'. "
            f"Add an entry to EXPECTED_SHA256 in this script."
        )
    if actual != expected:
        raise SystemExit(
            f"error: SHA256 mismatch for {name}.\n"
            f"  expected: {expected}\n"
            f"  actual:   {actual}\n"
            f"Inspect {cache_path} before trusting it. To bump intentionally,\n"
            f"review the new file for unsafe unicode (homoglyphs, RTL overrides)\n"
            f"and update EXPECTED_SHA256 in {os.path.basename(__file__)}."
        )

    return json.loads(raw)


def normalize_shortcodes(value) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    return list(value)


def main() -> int:
    print("Building emoji database…")
    sources = {name: fetch(name, url) for name, url in SOURCES.items()}
    compact = sources["compact"]
    iamcal = sources["iamcal"]
    emojibase = sources["emojibase"]
    github = sources["github"]

    out = []
    for entry in compact:
        hexcode = entry["hexcode"]

        # Merge shortcodes from all sources, dedup, prefer iamcal first.
        shortcodes: list[str] = []
        seen: set[str] = set()
        for source in (iamcal, github, emojibase):
            for s in normalize_shortcodes(source.get(hexcode)):
                key = s.lower()
                if key in seen:
                    continue
                seen.add(key)
                shortcodes.append(s)

        if not shortcodes:
            # No name to type — skip (most flag/regional indicators get pruned here).
            continue

        out.append({
            "h": hexcode,
            "e": entry["unicode"],
            "n": entry["label"],
            "s": shortcodes,
            "t": entry.get("tags", []),
            "g": entry.get("group", -1),
            "o": entry.get("order", 0),
            # True if the emoji has skin-tone variants in emojibase. The Swift
            # side uses this to decide whether to append the user's chosen
            # skin-tone modifier at insertion time.
            "k": bool(entry.get("skins")),
        })

    out.sort(key=lambda e: e["o"])

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

    size = os.path.getsize(OUT)
    print(f"Wrote {len(out)} emoji to {OUT} ({size/1024:.1f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
