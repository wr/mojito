#!/usr/bin/env python3
"""Regenerate Sources/Mojito/App/EggStrings.swift from a plaintext keyword list.

The trigger keywords for the easter eggs are kept obfuscated in source so a
casual reader of the repo can't grep them out. Plaintext lives only on your
local disk while this script runs — never committed.

Usage:
    python3 scripts/build_egg_strings.py < keywords.txt > Sources/Mojito/App/EggStrings.swift

`keywords.txt` is a sequence of `label  text` pairs, one per line, separated
by whitespace. The label maps to a `static let <label>: String` declaration
in the output. Lines beginning with `#` are comments. Example:

    # Post-discovery trigger reveals (full `:keyword:` form).
    k01  :mojito:
    k03  :moof:
    ...
    # Picker pinned-row labels (no surrounding colons).
    k04Label  confetti
    k05Label  pride

After running, eyeball the diff before committing. Do NOT commit the
plaintext keywords.txt — keep it on disk only as long as you need it.

Encoding: byte i is `plaintext[i] XOR ((0xA5 + i) & 0xFF)`. Trivially
reversible — defeats `strings(1)` and a casual repo skim, not a determined
reverser. To rotate the mask, change `XOR_BASE` here AND in the `decode`
helper emitted into EggStrings.swift, then re-run.
"""

import sys

XOR_BASE = 0xA5


def encode(text: str) -> list[int]:
    raw = text.encode("utf-8")
    return [b ^ ((XOR_BASE + i) & 0xFF) for i, b in enumerate(raw)]


def main() -> None:
    entries: list[tuple[str, str]] = []
    for lineno, raw in enumerate(sys.stdin, start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            sys.exit(f"line {lineno}: expected `<label> <text>`, got {raw!r}")
        label, text = parts
        entries.append((label, text))

    if not entries:
        sys.exit("no entries on stdin")

    out = sys.stdout.write
    out("import Foundation\n\n")
    out("/// Decoded trigger strings for the hidden effects. Keyed by opaque id —\n")
    out("/// match the case raw values on `EasterEgg`. The plaintext form is never\n")
    out("/// in source; bytes below decode at runtime via a per-index XOR mask.\n")
    out("///\n")
    out("/// Encoding: bytewise XOR against a rolling key starting at `0x%02X`,\n" % XOR_BASE)
    out("/// advancing `+1` per byte. Trivially reversible to anyone determined\n")
    out("/// enough, but it defeats `strings <binary>` and a casual scan of the\n")
    out("/// source.\n")
    out("///\n")
    out("/// Regenerate via `python3 scripts/build_egg_strings.py < keywords.txt`\n")
    out("/// (`keywords.txt` is kept out of git — see the script header).\n")
    out("enum EggStrings {\n")
    out("    private static func decode(_ bytes: [UInt8]) -> String {\n")
    out("        var out = [UInt8]()\n")
    out("        out.reserveCapacity(bytes.count)\n")
    out("        for (i, b) in bytes.enumerated() {\n")
    out("            out.append(b ^ UInt8((0x%02X &+ i) & 0xFF))\n" % XOR_BASE)
    out("        }\n")
    out("        return String(decoding: out, as: UTF8.self)\n")
    out("    }\n\n")
    for label, text in entries:
        bytes_ = encode(text)
        bytes_str = ", ".join(f"0x{b:02x}" for b in bytes_)
        out(f"    static let {label}: String = decode([{bytes_str}])\n")
    out("}\n")


if __name__ == "__main__":
    main()
