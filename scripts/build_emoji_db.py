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

BASE = "https://raw.githubusercontent.com/milesj/emojibase/master/packages/data"
EN_REPO = f"{BASE}/en"
SOURCES = {
    "compact":   f"{EN_REPO}/compact.raw.json",
    "iamcal":    f"{EN_REPO}/shortcodes/iamcal.raw.json",
    "emojibase": f"{EN_REPO}/shortcodes/emojibase.raw.json",
    "github":    f"{EN_REPO}/shortcodes/github.raw.json",
}

# Locales with localized shortcode coverage. `cldr-native` preserves
# diacritics (cœur_rouge, grünes_herz, corazón_rojo); `cldr` is ASCII-
# transliterated (coeur_rouge, gruenes_herz, corazon_rojo). Bundling both
# flavors per locale gives accent-fold tolerance for free — typing either
# form matches the same emoji.
#
# Locale codes are emojibase's (lowercase, dash-region). The Swift loader
# maps system `Locale.preferredLanguages` codes (`en-GB`, `zh-Hans`, …) to
# these. ar/fa/he aren't in emojibase yet — they'd need raw CLDR XML.
LOCALES = [
    "de", "en-gb", "es", "fr", "hi", "it", "ja", "ko",
    "nl", "pl", "pt", "ru", "zh", "zh-hant",
]
for _loc in LOCALES:
    SOURCES[f"{_loc}-cldr-native"] = f"{BASE}/{_loc}/shortcodes/cldr-native.raw.json"
    SOURCES[f"{_loc}-cldr"]        = f"{BASE}/{_loc}/shortcodes/cldr.raw.json"

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
    # Locale shortcode digests — Unicode-3.0 licensed, all data ultimately
    # sourced from Unicode CLDR. To bump: run `--print-shas`, review the
    # cached files, paste new digests here.
    "de-cldr-native":        "a183ed84c526fab459499454d921b1efae0eea29394dcb3be25007e4cb5ff83b",
    "de-cldr":               "49d91e564accf2246f91c2f5182361c80c640c5ea23284a7cda5865de99e07e8",
    "en-gb-cldr-native":     "f00225829fbce2310538a484e64eb3521603df146da144001c55509888d59da0",
    "en-gb-cldr":            "5a4646b8335a6fcf4894fd8986db507e216723aef2f34dee13659d9f6edfcb12",
    "es-cldr-native":        "dea34c9f27b53f01039ca2e0c5d94aec4ff8328b316a6f074d86158242345d23",
    "es-cldr":               "3c6dd3b5b77c6c2cca5533cf6418fd2c4ef3fe8366440c03507c76cafc7b278a",
    "fr-cldr-native":        "7187ff120cbf54b59440975ec61a0fef332deea985383b7c55c33b1ad2cb8c6b",
    "fr-cldr":               "1ec0bd045b29dbd8f8ef80b732ce43761bf343ac177403504d6ffc617792906b",
    "hi-cldr-native":        "bc576f75827dc110ef06f01bf90a84a24abb9ebc846bbee8158552d0131c1a02",
    "hi-cldr":               "66984770f4e8eaa0f1f22b8083f5f71b198c97741524c51fd7fc0975a07ebf00",
    "it-cldr-native":        "9cf87ef32e050050f601c7e8515e012efd27352c0beeef419eb695244a16b993",
    "it-cldr":               "43423795a6fece90532a7d98019b305bce4af6407a222e52151ae44c5276045d",
    "ja-cldr-native":        "49e79ccf55c40a4de98bb874353852b6cd42793f9c29a70c8d8bba5d42331468",
    "ja-cldr":               "aab3dbb0c7ee3f7e5eb3b4de7db5527ad9065655d9dd7c4e9c33faae3083eb84",
    "ko-cldr-native":        "5d0fbcd9ba0167f7e846c635f46e6fb9ab83b7382b15262d1e257c09f9da6385",
    "ko-cldr":               "040680f21f19934c96c4506a0678e5a698244364c2e1f360e4aa113b5a130be2",
    "nl-cldr-native":        "6fe88354bb0099aa7f2587da55584535ff01cbac4035da622aac9b46d9de4c93",
    "nl-cldr":               "fbe1cbc4fb499093d29a2388373de051fd88e198483f860c0f16c05dddaaf6b8",
    "pl-cldr-native":        "05806269040b046496e044c2832fe21a74949bbdcc3d01498a44146c1be299c1",
    "pl-cldr":               "fb7e8dc5ca4add2536ead9e87c471dee5946966e890e2aa32f3964ad6c179964",
    "pt-cldr-native":        "13d2ad39a6142d462d7dcef1a47f7988a2d9d2ed4c2a8c12c9e9a5a59cc57d6a",
    "pt-cldr":               "b83176ace7a4b37f3d52d4d6381ce093cbb868a68d764e0408a187df904ef5f3",
    "ru-cldr-native":        "4be607703266d1c3daaba057f81ab1289d8a2b36b0e29da8194b32b0013d82c0",
    "ru-cldr":               "02ba0d0d0dd07233baeba2054c11c284282fc4ad3f78547cb918de1b55962547",
    "zh-cldr-native":        "28567bc7446971771ff6f77f7e2ce2df533b33c9a19ae08fef172be01cd34732",
    "zh-cldr":               "8514a4725d991c2c25efd0cac65b70c38d745fc5cbfd6d32be1b857c69998f48",
    "zh-hant-cldr-native":   "901481b49b72dbf1eed7bde50e80491b43b16f98d8197b3d28ab6a26716f2a98",
    "zh-hant-cldr":          "5c6387043e92c39118e5f41480b38dd17917f649a8a371e934a7f576c3c6db1e",
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
    # On first locale run, the SHA pins are unset. Allow `--print-shas` to
    # bypass enforcement once, print the actual digests, and exit. Operator
    # reviews the cached files, pastes the digests into EXPECTED_SHA256, and
    # re-runs the script normally.
    if "--print-shas" in sys.argv:
        return print_shas()

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

        # Locale-specific shortcodes (CLDR-derived). Stored as nested dict
        # keyed by locale code so Mojito can pick the ones matching the
        # user's `Locale.preferredLanguages` at load time.
        loc_codes: dict[str, list[str]] = {}
        for locale in LOCALES:
            seen_loc: set[str] = set()
            loc_list: list[str] = []
            for variant in (f"{locale}-cldr-native", f"{locale}-cldr"):
                src = sources.get(variant)
                if not src:
                    continue
                for s in normalize_shortcodes(src.get(hexcode)):
                    key = s.lower()
                    if key in seen_loc:
                        continue
                    seen_loc.add(key)
                    loc_list.append(s)
            if loc_list:
                loc_codes[locale] = loc_list

        item = {
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
        }
        if loc_codes:
            # Locale-keyed shortcode lists — Swift `EmojiDatabase` merges
            # these into the searchable haystacks for the user's preferred
            # languages.
            item["l"] = loc_codes
        out.append(item)

    out.sort(key=lambda e: e["o"])

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

    size = os.path.getsize(OUT)
    print(f"Wrote {len(out)} emoji to {OUT} ({size/1024:.1f} KB)")
    return 0


def print_shas() -> int:
    """Fetch every source bypassing SHA enforcement; print the digests so
    the operator can paste them into EXPECTED_SHA256 after manual review."""
    print("Fetching and hashing all sources (SHA enforcement bypassed)…")
    for name, url in SOURCES.items():
        cache_path = os.path.join(CACHE, f"{name}.json")
        if not os.path.exists(cache_path):
            print(f"  fetching {name}…")
            with urllib.request.urlopen(url) as r:
                data = r.read()
            with open(cache_path, "wb") as f:
                f.write(data)
        with open(cache_path, "rb") as f:
            raw = f.read()
        print(f'    "{name}":'.ljust(28) + f' "{hashlib.sha256(raw).hexdigest()}",')
    print("\nReview the cached files in .emoji-cache/, paste these into")
    print("EXPECTED_SHA256 in this script, then re-run without --print-shas.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
