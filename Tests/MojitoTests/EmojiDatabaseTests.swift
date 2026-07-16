import Testing
@testable import Mojito

/// Smoke + lookup invariants for the bundled emoji corpus. The test host
/// bundles `emoji.json`, so `EmojiDatabase.shared` loads the real data.
@MainActor
struct EmojiDatabaseTests {

    @Test func loadsTheFullCorpus() {
        let db = EmojiDatabase.shared
        // emojibase ships ~1.9k entries; guard against an empty/failed load.
        #expect(db.all.count > 1000)
        // One indexed row per emoji, plus one per distinct symbol a custom
        // alias points at — aliasing a symbol adds it as a first-class row
        // (emoji aliases only augment their target's existing row).
        let aliasedSymbolRows = Set(
            AliasStore.shared.aliases
                .map(\.hexcode)
                .filter { $0.hasPrefix("SYM_") && SymbolsDatabase.byHexcode[$0] != nil }
        ).count
        #expect(db.indexed.count == db.all.count + aliasedSymbolRows)
    }

    @Test func exactLookupResolvesKnownShortcode() {
        #expect(EmojiDatabase.shared.exact("smile")?.character == "😄")
    }

    @Test func exactLookupIsCaseInsensitive() {
        let db = EmojiDatabase.shared
        let lower = db.exact("smile")
        #expect(lower != nil)
        #expect(db.exact("SMILE")?.hexcode == lower?.hexcode)
        #expect(db.exact("Smile")?.hexcode == lower?.hexcode)
    }

    @Test func exactLookupUnknownReturnsNil() {
        #expect(EmojiDatabase.shared.exact("definitely_not_a_shortcode_zzqx") == nil)
    }

    @Test func hexcodeIndexMatchesShortcodeIndex() throws {
        let db = EmojiDatabase.shared
        let smile = try #require(db.exact("smile"))
        #expect(db.byHexcode[smile.hexcode]?.character == smile.character)
    }

    @Test func componentModifiersAreExcluded() {
        let db = EmojiDatabase.shared
        // Group 2 (component): bare skin-tone + hair modifiers, never standalone.
        #expect(db.all.allSatisfy { $0.group != EmojiDatabase.componentGroup })
        // The reported case: the bare medium skin-tone swatch (🏽) is gone.
        #expect(db.byHexcode["1F3FD"] == nil)
        // And it doesn't surface in search.
        let hits = FuzzyMatcher.search(
            query: "medium", in: db, usage: [:],
            corpus: .emojiOnly, useFrequencyBoost: false, limit: 50
        )
        #expect(!hits.contains { $0.emoji.character == "🏽" })
    }

    @Test func indexedHaystacksIncludeEveryShortcode() throws {
        let db = EmojiDatabase.shared
        let smile = try #require(db.exact("smile"))
        let entry = try #require(db.indexed.first { $0.emoji.hexcode == smile.hexcode })
        // Haystacks are pre-lowercased `[Character]` arrays — one per shortcode.
        #expect(entry.haystacks.contains { $0.chars == Array("smile") })
    }
}
