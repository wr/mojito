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

    @Test func curatedShortcodeStillResolves() {
        // The character mutation must not break the existing shortcode-
        // based lookup the curated aliases rely on.
        let cmd = SymbolsDatabaseTests.indexed.first(where: { $0.emoji.shortcodes.contains("cmd") })
        #expect(cmd != nil)
        #expect(cmd?.emoji.character == "⌘")
    }
}
