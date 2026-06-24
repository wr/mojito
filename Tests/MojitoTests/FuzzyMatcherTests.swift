import Testing
@testable import Mojito

/// `FuzzyMatcher.search` ranking behaviour, exercised against the real
/// bundled corpus (the test host bundles `emoji.json`). Assertions are
/// data-shape invariants — prefix-tier precedence, the frequency boost,
/// corpus scoping, the result cap — not magic scores, so scoring tweaks
/// don't force a rewrite. Easter-egg pinned rows are deliberately not
/// exercised here (their triggers live only as hashes).
@MainActor
struct FuzzyMatcherTests {

    private func search(
        _ query: String,
        corpus: SearchCorpus = .emojiOnly,
        usage: [String: Int] = [:],
        boost: Bool = false,
        limit: Int = 12
    ) -> [ScoredEmoji] {
        FuzzyMatcher.search(
            query: query,
            in: EmojiDatabase.shared,
            usage: usage,
            corpus: corpus,
            useFrequencyBoost: boost,
            limit: limit
        )
    }

    /// Real (non-pinned) results — pinned/sentinel rows carry group -1.
    private func realResults(_ scored: [ScoredEmoji]) -> [ScoredEmoji] {
        scored.filter { $0.emoji.group != -1 }
    }

    @Test func emptyQueryReturnsNothing() {
        #expect(search("").isEmpty)
    }

    @Test func resultCapIsRespected() {
        // "a" matches a huge slice of the corpus; the cap must still hold.
        #expect(search("a", limit: 5).count <= 5)
    }

    @Test func commonQueryReturnsMatches() {
        #expect(!search("smile").isEmpty)
    }

    @Test func prefixMatchesOutrankEmbedded() throws {
        // "smile" has shortcodes that start with it (smile, smiley, …); the
        // prefix tier sorts ahead of embedded matches, so the top real
        // result's matched shortcode must begin with the query.
        let results = realResults(search("smile"))
        try #require(!results.isEmpty)
        #expect(results.first!.matchedShortcode.lowercased().hasPrefix("smile"))
    }

    @Test func frequencyBoostPromotesUsedEmoji() throws {
        // "smile" has several shortcodes that start with it, so the top
        // results all sit in the prefix tier. The boost is capped at +5.0
        // (about a full consecutive match), so heavily using a lower-ranked
        // prefix result must lift it toward the front of that tier. Staying
        // within one tier avoids the prefix-vs-embedded barrier, which no
        // score boost can cross.
        let base = realResults(search("smile", boost: true))
        try #require(base.count >= 3)
        let target = base[2].emoji.hexcode
        let boosted = realResults(search("smile", usage: [target: 10_000], boost: true))
        let boostedIdx = boosted.firstIndex { $0.emoji.hexcode == target }!
        #expect(boostedIdx < 2)
    }

    @Test func frequencyBoostNeverDemotes() throws {
        // With the boost off, usage counts must not change the order.
        let unboosted = realResults(search("heart", boost: false))
        try #require(unboosted.count >= 2)
        let target = unboosted.last!.emoji.hexcode
        let baseIdx = unboosted.firstIndex { $0.emoji.hexcode == target }!
        let withUsageButNoBoost = realResults(
            search("heart", usage: [target: 1000], boost: false)
        )
        let idx = withUsageButNoBoost.firstIndex { $0.emoji.hexcode == target }!
        #expect(idx == baseIdx)
    }

    @Test func symbolsOnlyCorpusFindsCuratedSymbol() {
        let results = search("cmd", corpus: .symbolsOnly)
        #expect(results.contains { $0.emoji.character == "⌘" })
    }

    @Test func emojiOnlyCorpusExcludesSymbols() {
        let results = search("cmd", corpus: .emojiOnly)
        #expect(!results.contains { $0.emoji.character == "⌘" })
    }

    @Test func emojiAndSymbolsCorpusSpansBoth() {
        // The combined corpus should surface emoji for an emoji query and
        // symbols for a symbol query.
        #expect(!search("smile", corpus: .emojiAndSymbols).isEmpty)
        #expect(search("cmd", corpus: .emojiAndSymbols).contains { $0.emoji.character == "⌘" })
    }

    @Test func tagKeywordSurfacesEmoji() {
        // "meditation" is only a keyword (tag) on 🧘 — its shortcodes are
        // person_in_lotus_position / lotus_position, neither a subsequence of
        // the query. Before tags were indexed this returned nothing relevant.
        #expect(search("meditation").contains { $0.emoji.hexcode.hasPrefix("1F9D8") })
    }

    @Test func conceptKeywordSurfacesUnshortcodedEmoji() {
        // 😀 (grinning) carries "happy" only as a tag; "happy" isn't a
        // subsequence of grinning/grinning_face.
        #expect(search("happy").contains { $0.emoji.hexcode == "1F600" })
    }

    @Test func shortcodeMatchOutranksTagMatch() throws {
        // For "smile", 😄 (shortcode `smile`) sits in the prefix tier; 😀
        // (grinning) matches "smile" only via a tag. The shortcode match must
        // rank ahead of the tag-only one whenever both surface.
        let results = realResults(search("smile"))
        let shortcodeIdx = results.firstIndex { $0.emoji.hexcode == "1F604" }
        let tagOnlyIdx = results.firstIndex { $0.emoji.hexcode == "1F600" }
        try #require(shortcodeIdx != nil)
        if let tagOnlyIdx { #expect(shortcodeIdx! < tagOnlyIdx) }
    }
}
