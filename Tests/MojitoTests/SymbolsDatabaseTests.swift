import Testing
@testable import Mojito

/// SymbolsDatabase pins text-style presentation on scalars that would
/// otherwise render in color on macOS — VS15 (U+FE0E) gets appended for
/// any scalar with the Unicode `Emoji` property.
struct SymbolsDatabaseTests {
    private static let indexed = SymbolsDatabase.indexed()

    private func entry(forCodepoint cp: UInt32) -> IndexedEmoji? {
        let needle = String(format: "SYM_U%X", cp)
        return Self.indexed.first(where: { $0.emoji.hexcode == needle })
    }

    @Test func emojiPropertyScalarGetsTextVariationSelector() {
        // U+2648 ARIES has Emoji=true → must ship with trailing VS15.
        let aries = entry(forCodepoint: 0x2648)
        #expect(aries != nil)
        let scalars = Array(aries!.emoji.character.unicodeScalars)
        #expect(scalars.first?.value == 0x2648)
        #expect(scalars.last?.value == 0xFE0E)
    }

    @Test func nonEmojiScalarIsLeftBare() {
        // U+2318 PLACE OF INTEREST SIGN (⌘) has no Emoji property — must
        // not get a trailing variation selector.
        let cmd = SymbolsDatabaseTests.indexed.first(where: { $0.emoji.character.hasPrefix("⌘") })
        #expect(cmd != nil)
        let scalars = Array(cmd!.emoji.character.unicodeScalars)
        #expect(scalars.count == 1)
        #expect(scalars.first?.value == 0x2318)
    }

    @Test func unrenderableScalarIsDroppedFromCorpus() {
        // U+2BE8 STAR WITH LEFT HALF BLACK is in the swept range and has a
        // Unicode name, but no font on macOS 14/15 carries a glyph for it.
        // The Core Text cascade gate should excise it.
        let hex = String(format: "SYM_U%X", 0x2BE8)
        #expect(!SymbolsDatabaseTests.indexed.contains(where: { $0.emoji.hexcode == hex }))
    }

    @Test func latin1CurrencySignsAreReachable() {
        // £ ¢ ¥ live at U+00A2–A5, outside every range in `symbolRanges`, so
        // they only reach the picker through a curated alias. Each must be
        // findable by the terms people actually type, not just its Unicode name.
        let expected: [(term: String, character: String)] = [
            ("pound", "£"), ("sterling", "£"), ("gbp", "£"),
            ("cent", "¢"),
            ("yen", "¥"), ("yuan", "¥"),
        ]
        for (term, character) in expected {
            let hit = SymbolsDatabaseTests.indexed.first(where: { $0.emoji.shortcodes.contains(term) })
            #expect(hit?.emoji.character == character, "expected \(character) for \"\(term)\"")
        }
    }

    @Test func curatedSymbolsAreFindableBySearchTerm() {
        // Curated aliases give clean, searchable labels for glyphs whose Unicode
        // names are awkward or wrong. Notably "lambda": U+03BB's Unicode name is
        // "GREEK SMALL LETTER LAMDA", so the sweep alone can't match "lambda".
        let expected: [(term: String, character: String)] = [
            ("lambda", "λ"), ("delta", "δ"), ("Delta", "Δ"), ("omega", "ω"),
            ("half", "½"), ("squared", "²"), ("cubed", "³"),
            ("spanish_question", "¿"), ("micro", "µ"),
        ]
        for (term, character) in expected {
            let hit = SymbolsDatabaseTests.indexed.first(where: { $0.emoji.shortcodes.contains(term) })
            #expect(hit?.emoji.character == character, "expected \(character) for \"\(term)\"")
        }
    }

    @Test func newlySweptBlocksAreReachable() {
        // Blocks below U+2000 (and Braille / CJK punctuation) used to fall
        // outside symbolRanges entirely. Spot-check one scalar from each.
        func present(_ cp: UInt32) -> Bool {
            SymbolsDatabaseTests.indexed.contains(where: {
                $0.emoji.character.unicodeScalars.first?.value == cp
            })
        }
        #expect(present(0x2801), "Braille ⠁")
        #expect(present(0x300C), "CJK bracket 「")
        #expect(present(0x00BD), "fraction ½")
        #expect(present(0x03C9), "greek ω")
    }

    @Test func nonGraphicScalarsAreExcluded() {
        // The general-category guard must drop soft hyphen (U+00AD, format) so
        // it doesn't surface as an invisible blank row.
        let softHyphen = SymbolsDatabaseTests.indexed.contains(where: {
            $0.emoji.character.unicodeScalars.first?.value == 0x00AD
        })
        #expect(!softHyphen)
    }

    @Test func curatedShortcodeStillResolves() {
        // The character mutation must not break the existing shortcode-
        // based lookup the curated aliases rely on.
        let cmd = SymbolsDatabaseTests.indexed.first(where: { $0.emoji.shortcodes.contains("cmd") })
        #expect(cmd != nil)
        #expect(cmd?.emoji.character == "⌘")
    }
}
