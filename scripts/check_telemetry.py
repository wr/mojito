#!/usr/bin/env python3
"""Fail if the anonymous-stats pipeline has drifted across its layers.

Run in CI (.github/workflows/telemetry.yml) and locally:

    python3 scripts/check_telemetry.py

Telemetry flows through three places that must agree, in two files:

  1. Swift client  — features() + the totals payload in
     Sources/Mojito/Telemetry/TelemetryUploader.swift (what an install sends).
  2. Worker ingest — FEATURE_KEYS + TOTAL_KINDS in stats-worker/src/index.js
     (the allow-list; anything not here is silently dropped on receipt).
  3. Worker publish — PUBLIC_FEATURE_KEYS in the same file (the curated subset
     shown on mojito.wells.ee/stats).

When someone adds a feature flag or insertion counter and wires only one or
two of these, data goes missing with no error anywhere. This check is the
backstop — the telemetry analogue of check_localizations.py: every reported
feature must be allow-listed, and the published set must be a real subset.

To fix a reported gap:
  - feature drift  → add/remove the key in BOTH features() and FEATURE_KEYS.
  - publish gap    → every PUBLIC_FEATURE_KEYS entry must also be in FEATURE_KEYS.
  - totals drift   → keep the Swift `totals` payload keys and TOTAL_KINDS in sync.
A key can be ingested but not published (kept for the debug/internal view);
those are listed as a note, not a failure.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UPLOADER = ROOT / "Sources" / "Mojito" / "Telemetry" / "TelemetryUploader.swift"
WORKER = ROOT / "stats-worker" / "src" / "index.js"


def fail(msg: str) -> None:
    print(f"❌ {msg}")


def swift_block_keys(text: str, start: int) -> list[str]:
    """Keys of the bracketed dict literal beginning at the first `[` after
    `start`, matched to its closing `]` so nested dicts/arrays are handled."""
    i = text.index("[", start) + 1
    depth, j = 1, i
    while j < len(text) and depth:
        if text[j] == "[":
            depth += 1
        elif text[j] == "]":
            depth -= 1
        j += 1
    block = re.sub(r"//[^\n]*", "", text[i : j - 1])  # drop line comments
    return re.findall(r'"([A-Za-z][A-Za-z0-9_]*)"\s*:', block)


def js_array(text: str, name: str) -> list[str]:
    m = re.search(rf"const\s+{name}\s*=\s*\[(.*?)\]", text, re.DOTALL)
    if not m:
        return []
    return re.findall(r'"([A-Za-z][A-Za-z0-9_]*)"', m.group(1))


def dups(items: list[str]) -> list[str]:
    seen, out = set(), []
    for it in items:
        if it in seen and it not in out:
            out.append(it)
        seen.add(it)
    return out


def main() -> int:
    for p in (UPLOADER, WORKER):
        if not p.exists():
            sys.exit(f"missing file: {p}")

    swift = UPLOADER.read_text()
    worker = WORKER.read_text()

    feat_fn = swift.index("func features()")
    swift_features = swift_block_keys(swift, swift.index("return [", feat_fn))
    swift_totals = swift_block_keys(swift, swift.index('"totals":'))

    ingest = js_array(worker, "FEATURE_KEYS")
    public = js_array(worker, "PUBLIC_FEATURE_KEYS")
    total_kinds = js_array(worker, "TOTAL_KINDS")

    ok = True

    # No list may repeat a key.
    for label, items in [
        ("features()", swift_features), ("FEATURE_KEYS", ingest),
        ("PUBLIC_FEATURE_KEYS", public), ("TOTAL_KINDS", total_kinds),
        ('"totals" payload', swift_totals),
    ]:
        if not items:
            fail(f"could not parse any keys from {label} — has it moved or been renamed?")
            ok = False
        d = dups(items)
        if d:
            fail(f"{label} has duplicate keys: {', '.join(d)}")
            ok = False

    # 1. Client features() and the worker ingest allow-list must match exactly.
    sf, ik = set(swift_features), set(ingest)
    if sf - ik:
        fail("features() sends keys the worker drops (add to FEATURE_KEYS): "
             + ", ".join(sorted(sf - ik)))
        ok = False
    if ik - sf:
        fail("FEATURE_KEYS allow-lists keys the client never sends "
             "(remove, or add to features()): " + ", ".join(sorted(ik - sf)))
        ok = False

    # 2. Everything published must be ingestible.
    pk = set(public)
    if pk - ik:
        fail("PUBLIC_FEATURE_KEYS publishes keys not in FEATURE_KEYS: "
             + ", ".join(sorted(pk - ik)))
        ok = False

    # 3. Insertion totals: Swift payload keys vs worker TOTAL_KINDS.
    st, tk = set(swift_totals), set(total_kinds)
    if st != tk:
        if st - tk:
            fail("`totals` payload sends kinds the worker drops "
                 "(add to TOTAL_KINDS): " + ", ".join(sorted(st - tk)))
        if tk - st:
            fail("TOTAL_KINDS expects kinds the client never sends: "
                 + ", ".join(sorted(tk - st)))
        ok = False

    if not ok:
        return 1

    not_published = [k for k in ingest if k not in pk]
    print(f"✓ telemetry in sync — {len(ingest)} feature keys "
          f"({len(public)} published), {len(total_kinds)} insertion totals")
    if not_published:
        print(f"  note: ingested but not on the public page: {', '.join(not_published)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
