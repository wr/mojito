import Foundation

/// Curated Unicode symbols plus everything else with a Unicode name in the
/// common symbol blocks (arrows, math, misc technical, dingbats, mahjong,
/// dominoes, playing cards, etc.). Opt-in via the experimental toggle.
///
/// Two layers:
///   1. `curatedAliases` — hand-picked entries with short, memorable shortcodes
///      ("cmd" for ⌘, "arrow_right" for →). These take precedence.
///   2. Programmatic entries — every other named scalar in `symbolRanges`,
///      with shortcodes derived from the official Unicode name ("PLACE OF
///      INTEREST SIGN" → "place_of_interest_sign"). Long but searchable —
///      typing `:domino` will fuzzy-match all 100 domino tiles.
enum SymbolsDatabase {
    static func indexed() -> [IndexedEmoji] {
        var seenCharacters = Set<String>()
        var result: [IndexedEmoji] = []

        // 1. Curated entries first — short, memorable aliases override the
        //    long Unicode names for chars we care about.
        for entry in curatedAliases {
            seenCharacters.insert(entry.character)
            let emoji = Emoji(
                hexcode: "SYM_" + entry.shortcodes[0],
                character: entry.character,
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

        // 2. Programmatic sweep — every named scalar in the symbol ranges,
        //    skipping anything the curated set already covered.
        for range in symbolRanges {
            for codepoint in range {
                guard let scalar = Unicode.Scalar(codepoint) else { continue }
                let char = String(scalar)
                if seenCharacters.contains(char) { continue }
                guard let name = scalar.properties.name, !name.isEmpty else { continue }

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

    private struct Alias {
        let character: String
        let shortcodes: [String]
    }

    /// Unicode ranges to sweep for named symbols. Picked to cover the macOS
    /// emoji picker's "Symbols" category and adjacent blocks. Skips letter,
    /// CJK, and private-use ranges.
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

    /// Hand-picked aliases — for chars where the Unicode name is awkward
    /// ("PLACE OF INTEREST SIGN" is not what anyone types). These also act
    /// as "secondary search terms" beyond the Unicode name.
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
