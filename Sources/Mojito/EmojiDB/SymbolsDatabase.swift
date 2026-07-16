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
                // Skip non-graphic scalars (soft hyphen, format/control marks,
                // unassigned slots in the swept ranges) — they'd otherwise pass
                // the font-render gate as invisible blank rows.
                switch scalar.properties.generalCategory {
                case .control, .format, .surrogate, .privateUse, .unassigned:
                    continue
                default:
                    break
                }
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
    /// Letter blocks (Latin accents, Cyrillic, CJK ideographs) are deliberately
    /// excluded — the per-keystroke fuzzy scan walks this whole corpus, so the
    /// ~90k ideographs alone would push search from µs into ms. Greek stays:
    /// its letters double as math/science symbols.
    private static let symbolRanges: [ClosedRange<Int>] = [
        0x00A1...0x00BF,    // Latin-1 symbols (£ ¥ § ± ² ³ µ ¶ ¼ ½ ¾ ¿ « » ¬ …)
        0x0370...0x03FF,    // Greek & Coptic (α β γ … Ω)
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
        0x2800...0x28FF,    // Braille patterns
        0x2900...0x297F,    // Supp arrows B
        0x2980...0x29FF,    // Misc math B
        0x2A00...0x2AFF,    // Supp math
        0x2B00...0x2BFF,    // Misc symbols and arrows
        0x3000...0x303F,    // CJK symbols & punctuation (、。「」《》)
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

        // Fractions & superscripts. Swept too (Latin-1), but the Unicode names
        // ("VULGAR FRACTION ONE HALF", "SUPERSCRIPT TWO") read terribly in the
        // picker — give them the labels people search for.
        .init(character: "½",  shortcodes: ["half", "one_half"]),
        .init(character: "¼",  shortcodes: ["quarter", "one_quarter"]),
        .init(character: "¾",  shortcodes: ["three_quarters"]),
        .init(character: "²",  shortcodes: ["squared", "sup2"]),
        .init(character: "³",  shortcodes: ["cubed", "sup3"]),
        .init(character: "¹",  shortcodes: ["sup1"]),

        // Greek. Cleaner than the swept names, and the sweep can't be searched
        // by "lambda" at all — Unicode spells U+03BB "GREEK SMALL LETTER LAMDA".
        // Capitalized aliases (Δ → "Delta") read distinct from lowercase in the
        // picker. ⌥-typeable letters that look like Latin (Α Β Ε…) are left to
        // the sweep.
        .init(character: "α",  shortcodes: ["alpha"]),
        .init(character: "β",  shortcodes: ["beta"]),
        .init(character: "γ",  shortcodes: ["gamma"]),
        .init(character: "δ",  shortcodes: ["delta"]),
        .init(character: "ε",  shortcodes: ["epsilon"]),
        .init(character: "ζ",  shortcodes: ["zeta"]),
        .init(character: "η",  shortcodes: ["eta"]),
        .init(character: "θ",  shortcodes: ["theta"]),
        .init(character: "ι",  shortcodes: ["iota"]),
        .init(character: "κ",  shortcodes: ["kappa"]),
        .init(character: "λ",  shortcodes: ["lambda"]),
        .init(character: "μ",  shortcodes: ["mu"]),
        .init(character: "ν",  shortcodes: ["nu"]),
        .init(character: "ξ",  shortcodes: ["xi"]),
        .init(character: "ο",  shortcodes: ["omicron"]),
        .init(character: "ρ",  shortcodes: ["rho"]),
        .init(character: "σ",  shortcodes: ["sigma"]),
        .init(character: "ς",  shortcodes: ["final_sigma"]),
        .init(character: "τ",  shortcodes: ["tau"]),
        .init(character: "υ",  shortcodes: ["upsilon"]),
        .init(character: "φ",  shortcodes: ["phi"]),
        .init(character: "χ",  shortcodes: ["chi"]),
        .init(character: "ψ",  shortcodes: ["psi"]),
        .init(character: "ω",  shortcodes: ["omega"]),
        .init(character: "Γ",  shortcodes: ["Gamma"]),
        .init(character: "Δ",  shortcodes: ["Delta"]),
        .init(character: "Θ",  shortcodes: ["Theta"]),
        .init(character: "Λ",  shortcodes: ["Lambda"]),
        .init(character: "Ξ",  shortcodes: ["Xi"]),
        .init(character: "Π",  shortcodes: ["Pi"]),
        .init(character: "Σ",  shortcodes: ["Sigma"]),
        .init(character: "Φ",  shortcodes: ["Phi"]),
        .init(character: "Ψ",  shortcodes: ["Psi"]),
        .init(character: "Ω",  shortcodes: ["Omega", "ohm"]),

        // Latin-1 punctuation people can't easily type
        .init(character: "¡",  shortcodes: ["inverted_exclamation", "spanish_exclamation"]),
        .init(character: "¿",  shortcodes: ["inverted_question", "spanish_question"]),
        .init(character: "µ",  shortcodes: ["micro"]),
        .init(character: "«",  shortcodes: ["lguillemet", "guillemet_left"]),
        .init(character: "»",  shortcodes: ["rguillemet", "guillemet_right"]),

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

        // Math & logic. All swept too, but the Unicode names are unsearchable
        // ("N-ARY UNION", "THERE EXISTS") — give them the terms people type.
        .init(character: "∫",  shortcodes: ["integral"]),
        .init(character: "∂",  shortcodes: ["partial", "differential"]),
        .init(character: "∇",  shortcodes: ["nabla", "del", "gradient"]),
        .init(character: "∈",  shortcodes: ["element_of", "elem"]),
        .init(character: "∉",  shortcodes: ["not_element", "not_in"]),
        .init(character: "⊂",  shortcodes: ["subset"]),
        .init(character: "⊆",  shortcodes: ["subset_equal"]),
        .init(character: "⊃",  shortcodes: ["superset"]),
        .init(character: "∪",  shortcodes: ["union"]),
        .init(character: "∩",  shortcodes: ["intersection", "intersect"]),
        .init(character: "∴",  shortcodes: ["therefore"]),
        .init(character: "∵",  shortcodes: ["because"]),
        .init(character: "∝",  shortcodes: ["proportional", "propto"]),
        .init(character: "∅",  shortcodes: ["empty_set", "emptyset", "null_set"]),
        .init(character: "∀",  shortcodes: ["forall", "for_all"]),
        .init(character: "∃",  shortcodes: ["exists", "there_exists"]),
        .init(character: "¬",  shortcodes: ["not", "negation", "logical_not"]),
        .init(character: "∧",  shortcodes: ["wedge", "logical_and", "conjunction"]),
        .init(character: "∨",  shortcodes: ["vee", "logical_or", "disjunction"]),
        .init(character: "⊕",  shortcodes: ["oplus", "xor", "direct_sum"]),
        .init(character: "≡",  shortcodes: ["equivalent", "identical", "equiv"]),
        .init(character: "≅",  shortcodes: ["congruent", "cong"]),
        .init(character: "∼",  shortcodes: ["sim", "similar"]),

        // More arrows — rotate/refresh and the mapping arrows the swept names
        // ("CLOCKWISE OPEN CIRCLE ARROW", "RIGHTWARDS ARROW FROM BAR") bury.
        .init(character: "↔",  shortcodes: ["left_right", "leftright"]),
        .init(character: "↕",  shortcodes: ["up_down", "updown"]),
        .init(character: "↻",  shortcodes: ["refresh", "reload", "rotate", "rotate_cw"]),
        .init(character: "↺",  shortcodes: ["rotate_ccw", "undo_rotate"]),
        .init(character: "↦",  shortcodes: ["mapsto", "maps_to"]),

        // Typography & editorial marks
        .init(character: "†",  shortcodes: ["dagger", "obelisk"]),
        .init(character: "‡",  shortcodes: ["double_dagger", "ddagger", "diesis"]),
        .init(character: "№",  shortcodes: ["numero", "numero_sign"]),
        .init(character: "′",  shortcodes: ["prime", "minutes", "feet"]),
        .init(character: "″",  shortcodes: ["double_prime", "seconds", "inches"]),
        .init(character: "‰",  shortcodes: ["permille", "per_mille"]),
        .init(character: "·",  shortcodes: ["middot", "interpunct", "middle_dot"]),
        .init(character: "‽",  shortcodes: ["interrobang"]),
        .init(character: "※",  shortcodes: ["reference_mark", "kome"]),
        .init(character: "℅",  shortcodes: ["care_of", "c_o"]),
        .init(character: "℠",  shortcodes: ["service_mark", "sm"]),

        // Plain-text checkboxes & bullets (todo lists in any field)
        .init(character: "☐",  shortcodes: ["checkbox", "ballot", "unchecked"]),
        .init(character: "☑",  shortcodes: ["checkbox_checked", "ballot_check", "checked"]),
        .init(character: "☒",  shortcodes: ["checkbox_x", "ballot_x", "crossed"]),
        .init(character: "◦",  shortcodes: ["white_bullet", "hollow_bullet"]),
        .init(character: "‣",  shortcodes: ["triangle_bullet", "tri_bullet"]),

        // Music notation
        .init(character: "♩",  shortcodes: ["quarter_note"]),
        .init(character: "♪",  shortcodes: ["note", "eighth_note"]),
        .init(character: "♫",  shortcodes: ["notes", "beamed_notes"]),
        .init(character: "♭",  shortcodes: ["flat", "flat_sign"]),
        .init(character: "♮",  shortcodes: ["natural", "natural_sign"]),
        .init(character: "♯",  shortcodes: ["sharp", "sharp_sign"]),

        // Extra fractions (⅓ ⅔ read terribly as "VULGAR FRACTION ONE THIRD")
        .init(character: "⅓",  shortcodes: ["one_third", "third"]),
        .init(character: "⅔",  shortcodes: ["two_thirds"]),

        //  Apple logo (U+F8FF). A private-use codepoint only Apple's system
        // fonts draw — renders here and in any Apple app, but pastes as tofu on
        // Windows/Android/most web fonts. It's why the programmatic sweep skips
        // it (PUA is filtered out); curated entries bypass that render gate, so
        // it's opt-in and the portability trade-off is the user's to make.
        .init(character: "\u{F8FF}", shortcodes: ["apple", "apple_logo"]),
    ]
}
