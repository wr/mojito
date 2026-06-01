import AppKit
import CoreText
import Foundation

/// Two layers: hand-picked aliases (`cmd` → ⌘) take precedence over the
/// programmatic sweep that derives shortcodes from Unicode names
/// (`PLACE OF INTEREST SIGN` → `place_of_interest_sign`). Opt-in.
enum SymbolsDatabase {
    /// `SYM_…` hexcode → symbol, for resolving a pinned Quick Access slot.
    /// Built once on first access (the sweep is the slow part); only touched
    /// when a symbol is actually pinned.
    static let byHexcode: [String: Emoji] = Dictionary(
        indexed().map { ($0.emoji.hexcode, $0.emoji) },
        uniquingKeysWith: { first, _ in first }
    )

    static func indexed() -> [IndexedEmoji] {
        var seenCharacters = Set<String>()
        var result: [IndexedEmoji] = []

        for entry in curatedAliases {
            let char = textPresentation(entry.character)
            seenCharacters.insert(char)
            let emoji = Emoji(
                hexcode: "SYM_" + entry.shortcodes[0],
                character: char,
                label: entry.shortcodes[0],
                shortcodes: entry.shortcodes,
                tags: [],
                group: 99,
                order: 100_000,
                supportsSkinTone: false
            )
            let haystacks = entry.shortcodes.map {
                EmojiHaystack(display: $0, chars: Array($0.lowercased()))
            }
            result.append(IndexedEmoji(emoji: emoji, haystacks: haystacks))
        }

        // Programmatic sweep — every other named scalar in symbolRanges.
        for range in symbolRanges {
            for codepoint in range {
                guard let scalar = Unicode.Scalar(codepoint) else { continue }
                let char = textPresentation(String(scalar))
                if seenCharacters.contains(char) { continue }
                guard let name = scalar.properties.name, !name.isEmpty else { continue }
                // Many scalars in these ranges have a Unicode name but no
                // glyph anywhere in macOS's font cascade. Without this
                // gate they show up in the picker as ?-tofu rows.
                guard systemFontCanRender(char) else { continue }

                let shortcode = name
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "-", with: "_")

                let emoji = Emoji(
                    hexcode: String(format: "SYM_U%X", codepoint),
                    character: char,
                    label: shortcode,
                    shortcodes: [shortcode],
                    tags: [],
                    group: 99,
                    order: 100_000 + codepoint,
                    supportsSkinTone: false
                )
                let haystack = EmojiHaystack(display: shortcode, chars: Array(shortcode))
                result.append(IndexedEmoji(emoji: emoji, haystacks: [haystack]))
                seenCharacters.insert(char)
            }
        }

        return result
    }

    /// Scalars with the Unicode `Emoji` property render in color on macOS
    /// unless explicitly pinned to text style with VS15 (U+FE0E). Without
    /// this, ::aries: returned ♈️ (emoji) where the picker expects ♈︎.
    /// No-op for scalars that have no emoji presentation (⌘, ←, π, …).
    private static func textPresentation(_ s: String) -> String {
        guard let scalar = s.unicodeScalars.first, scalar.properties.isEmoji else {
            return s
        }
        return s + "\u{FE0E}"
    }

    /// Asks the actual rendering cascade whether anything but Apple's
    /// `LastResort` fallback font handles `s`. LastResort is what draws
    /// those `?`-in-a-box placeholder glyphs; non-zero glyphs from it
    /// look rendered but read as tofu to the user. Real fonts in the
    /// cascade (SF Pro, Apple Color Emoji, Apple Symbols, etc.) all
    /// pass.
    private static func systemFontCanRender(_ s: String) -> Bool {
        guard let font = CTFontCreateUIFontForLanguage(.system, 13, nil) else {
            return true
        }
        let attr = NSAttributedString(string: s, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attr)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return true }
        for run in runs {
            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { return false }
            var glyphs = [CGGlyph](repeating: 0, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            if glyphs.contains(0) { return false }
            let attrs = CTRunGetAttributes(run) as NSDictionary
            guard let runFont = attrs[kCTFontAttributeName as NSString] else { return false }
            let name = CTFontCopyPostScriptName(runFont as! CTFont) as String
            if name == "LastResort" { return false }
            // Even with VS15 appended (see `textPresentation`), color-only
            // scalars (✅ ✨ ✊ ✏ …) have no monochrome glyph, so Core Text
            // resolves them to Apple Color Emoji — they'd render as color
            // emoji among the text-style symbols. Drop them; they're already
            // reachable in the emoji categories. Scalars with a real text glyph
            // (♈︎, ✂︎, …) resolve to a text font and stay.
            if name.contains("Emoji") { return false }
        }
        return true
    }

    private struct Alias {
        let character: String
        let shortcodes: [String]
    }

    /// Covers the macOS emoji picker's "Symbols" category and adjacent blocks.
    private static let symbolRanges: [ClosedRange<Int>] = [
        0x2000...0x206F,    // General punctuation
        0x2070...0x209F,    // Super/subscripts
        0x20A0...0x20CF,    // Currency
        0x2100...0x214F,    // Letterlike (℃ ℉ № ™)
        0x2150...0x218F,    // Number forms (½ ⅓)
        0x2190...0x21FF,    // Arrows
        0x2200...0x22FF,    // Math operators (∀ ∃ ∅ ∈)
        0x2300...0x23FF,    // Misc technical (⌘ ⌥ ⌫ ⎋)
        0x2400...0x243F,    // Control pictures (␣)
        0x2440...0x245F,    // OCR
        0x2460...0x24FF,    // Enclosed alphanumerics (① ② ⓐ)
        0x2500...0x257F,    // Box drawing
        0x2580...0x259F,    // Block elements
        0x25A0...0x25FF,    // Geometric shapes
        0x2600...0x26FF,    // Misc symbols (☀ ☁ ☃ ♠ ♣ ♥ ♦ ♔)
        0x2700...0x27BF,    // Dingbats (✓ ✗ ❤ ✉ ✏)
        0x27C0...0x27EF,    // Misc math A
        0x27F0...0x27FF,    // Supp arrows A
        0x2900...0x297F,    // Supp arrows B
        0x2980...0x29FF,    // Misc math B
        0x2A00...0x2AFF,    // Supp math
        0x2B00...0x2BFF,    // Misc symbols and arrows
        0x1F000...0x1F02F,  // Mahjong tiles
        0x1F030...0x1F09F,  // Domino tiles
        0x1F0A0...0x1F0FF,  // Playing cards
    ]

    /// Hand-picked aliases for chars where the Unicode name is awkward
    /// (no one types "PLACE OF INTEREST SIGN"). Also adds search synonyms.
    private static let curatedAliases: [Alias] = [
        // Keyboard modifiers
        .init(character: "⌘",  shortcodes: ["cmd", "command"]),
        .init(character: "⌥",  shortcodes: ["option", "alt"]),
        .init(character: "⇧",  shortcodes: ["shift"]),
        .init(character: "⌃",  shortcodes: ["control", "ctrl"]),
        .init(character: "⎋",  shortcodes: ["escape", "esc"]),
        .init(character: "⏎",  shortcodes: ["return", "enter"]),
        .init(character: "⌫",  shortcodes: ["delete", "backspace"]),
        .init(character: "⌦",  shortcodes: ["forward_delete"]),
        .init(character: "⇥",  shortcodes: ["tab"]),
        .init(character: "⇪",  shortcodes: ["caps_lock"]),
        .init(character: "⏏",  shortcodes: ["eject"]),
        .init(character: "⏯",  shortcodes: ["play_pause"]),
        .init(character: "␣",  shortcodes: ["space"]),

        // Arrows
        .init(character: "→",  shortcodes: ["arrow_right", "right"]),
        .init(character: "←",  shortcodes: ["arrow_left", "left"]),
        .init(character: "↑",  shortcodes: ["arrow_up", "up"]),
        .init(character: "↓",  shortcodes: ["arrow_down", "down"]),
        .init(character: "⇒",  shortcodes: ["double_arrow_right"]),
        .init(character: "⇐",  shortcodes: ["double_arrow_left"]),

        // Math & punctuation
        .init(character: "∞",  shortcodes: ["infinity"]),
        .init(character: "±",  shortcodes: ["plus_minus"]),
        .init(character: "×",  shortcodes: ["times", "multiply"]),
        .init(character: "÷",  shortcodes: ["divide"]),
        .init(character: "≈",  shortcodes: ["approx"]),
        .init(character: "≠",  shortcodes: ["not_equal"]),
        .init(character: "≤",  shortcodes: ["less_equal"]),
        .init(character: "≥",  shortcodes: ["greater_equal"]),
        .init(character: "√",  shortcodes: ["sqrt"]),
        .init(character: "∑",  shortcodes: ["sum"]),
        .init(character: "π",  shortcodes: ["pi"]),
        .init(character: "°",  shortcodes: ["degree"]),

        // Currency. The Latin-1 currency signs (£ ¢ ¥, U+00A2–A5) fall
        // outside every block in `symbolRanges`, so without an explicit
        // entry they never reach the picker at all. The synonyms are terms
        // the Unicode name alone ("POUND SIGN") wouldn't fuzzy-match.
        .init(character: "£",  shortcodes: ["pound", "sterling", "gbp"]),
        .init(character: "¢",  shortcodes: ["cent", "cents"]),
        .init(character: "¥",  shortcodes: ["yen", "yuan", "rmb"]),

        // Marks & misc
        .init(character: "✓",  shortcodes: ["check_mark", "tick"]),
        .init(character: "✗",  shortcodes: ["x_mark", "cross"]),
        .init(character: "★",  shortcodes: ["star_filled"]),
        .init(character: "☆",  shortcodes: ["star_outline"]),
        .init(character: "•",  shortcodes: ["bullet"]),
        .init(character: "…",  shortcodes: ["ellipsis"]),
        .init(character: "—",  shortcodes: ["em_dash"]),
        .init(character: "–",  shortcodes: ["en_dash"]),
        .init(character: "‘",  shortcodes: ["lquote"]),
        .init(character: "’",  shortcodes: ["rquote", "apostrophe"]),
        .init(character: "“",  shortcodes: ["ldquote"]),
        .init(character: "”",  shortcodes: ["rdquote"]),
        .init(character: "©",  shortcodes: ["copyright"]),
        .init(character: "®",  shortcodes: ["registered"]),
        .init(character: "™",  shortcodes: ["tm", "trademark"]),
        .init(character: "§",  shortcodes: ["section"]),
        .init(character: "¶",  shortcodes: ["pilcrow"]),
    ]
}
