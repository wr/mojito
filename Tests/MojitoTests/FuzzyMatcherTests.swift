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
        // The swept symbol corpus stays out of .emojiOnly. A symbol the user
        // has explicitly aliased becomes a permanent indexed row, so it's the
        // one legitimate exception — assert no *un-aliased* swept symbol leaks.
        let aliasedSymbolHexes = Set(
            AliasStore.shared.aliases.map(\.hexcode).filter { $0.hasPrefix("SYM_") }
        )
        let leaked = search("cmd", corpus: .emojiOnly).filter {
            $0.emoji.hexcode.hasPrefix("SYM_") && !aliasedSymbolHexes.contains($0.emoji.hexcode)
        }
        #expect(leaked.isEmpty)
    }

    @Test func emojiAndSymbolsHasNoDuplicateHexcodes() {
        // A symbol targeted by an alias lives in both the indexed corpus and
        // the appended sweep; the combined search must surface it only once.
        // (Invariant holds regardless of which aliases the shared store has.)
        let db = EmojiDatabase.shared
        for q in ["cmd", "a", "star", "arrow", "note", "play"] {
            let hexes = FuzzyMatcher.search(
                query: q, in: db, usage: [:],
                corpus: .emojiAndSymbols, useFrequencyBoost: false, limit: 240
            ).map { $0.emoji.hexcode }
            #expect(Set(hexes).count == hexes.count, "duplicate hexcode for query \(q)")
        }
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

    @Test(arguments: [
        ("deploy", "1F680"),     // 🚀 — concept, not in any shortcode or CLDR tag
        ("ghosting", "1F47B"),   // 👻
        ("urgent", "1F6A8"),     // 🚨
    ])
    func emoogleConceptKeywordSurfacesEmoji(query: String, hexcode: String) {
        // Emoogle's keyword merge is what makes these reachable at all — none
        // of them appear in the emoji's shortcodes, label, or emojibase tags.
        #expect(search(query, limit: 12).contains { $0.emoji.hexcode == hexcode })
    }

    @Test func relevantTagMatchOutranksLooseSubsequence() throws {
        // ":happ" — 😀 matches the exact tag "happy"; ♿️ matches "happ" only as
        // a scattered subsequence of its "handicapped" shortcode (h‑a‑..‑p‑p).
        // The relevant exact-tag match must rank above the junk subsequence —
        // it didn't while tags carried a flat score penalty.
        let results = realResults(search("happ", limit: 2000))
        let happyIdx = try #require(results.firstIndex { $0.emoji.hexcode == "1F600" })
        let wheelchairIdx = try #require(results.firstIndex { $0.emoji.hexcode == "267F" })
        #expect(happyIdx < wheelchairIdx)
    }

    @Test(arguments: ["yeet", "lfg", "qwrtz"])
    func queryWithNoRealMatchReturnsNothing(query: String) {
        // Across ~23k haystacks something always matches as a scattered
        // subsequence — 🐞 for "yeet", 🥬 for "lfg". None of these words is in
        // the corpus, so an empty picker is the correct answer.
        #expect(realResults(search(query)).isEmpty)
    }

    @Test(arguments: [
        ("roket", "1F680"),   // 🚀 dropped 'c'
        ("sml", "1F604"),     // 😄 dropped vowels
        ("thnk", "1F914"),    // 🤔
    ])
    func floorKeepsTypoTolerance(query: String, hexcode: String) {
        // The floor is set below the cost of a one-character typo. Tightening
        // it to separate junk perfectly would break these, which users hit far
        // more often than they hit junk-only queries.
        #expect(search(query, limit: 12).contains { $0.emoji.hexcode == hexcode })
    }

    @Test(arguments: [
        ("ghosted", "1F47B"),    // 👻 — the keyword is "ghosting"/"ghost"
        ("deployed", "1F680"),   // 🚀
        ("cursed", "1F92C"),     // 🤬 — via "curse"
        ("launching", "1F680"),  // 🚀
    ])
    func inflectedQueryReachesItsKeyword(query: String, hexcode: String) {
        // fzy rejects a needle longer than its haystack, so these are
        // unreachable until the suffix comes off.
        #expect(search(query, limit: 12).contains { $0.emoji.hexcode == hexcode })
    }

    @Test func inventedStemDoesNotShadowTheRealOne() throws {
        // "movies" offers movy → movi → movie. `movy` isn't a word, but it
        // fuzzy-matches 🎑 (m‑o‑v‑y inside "moon_viewing_ceremony") well enough
        // to clear the floor — so without the is-it-a-real-term gate it wins
        // the race and 🎥 never surfaces.
        let results = search("movies", limit: 12).map(\.emoji.hexcode)
        let camera = try #require(results.firstIndex(of: "1F3A5"))  // 🎥 movie_camera
        // 🎑 may still show up as a weak match on the accepted stem — it just
        // can't be the reason the better stem was never tried.
        if let moon = results.firstIndex(of: "1F391") {             // 🎑
            #expect(camera < moon)
        }
    }

    @Test(arguments: [
        // Both exact terms — the longer one keeps more of the query.
        ("hoped", ["hope", "hop"]),
        ("bared", ["bare", "bar"]),
        // "smil" only prefixes "smile", so the exact term wins despite the tie
        // in neither being longer by much.
        ("smiled", ["smile", "smil"]),
        // "skie" is longer than both, but only prefixes "skier" — the exact
        // terms have to outrank it or ":skies" returns ⛷️.
        ("skies", ["sky", "ski", "skie"]),
        // "movi" prefixes "movie_camera"; "movie" is exact.
        ("movies", ["movie", "movi"]),
    ])
    func stemsAreOrderedByHowSolidlyTheyExist(query: String, expected: [String]) {
        let stems = FuzzyMatcher.acceptedStems(
            for: Array(query), in: EmojiDatabase.shared.indexed
        ).map { String($0) }
        #expect(stems == expected)
    }

    @Test func longerStemChangesWhatSurfaces() throws {
        // End-to-end: ":hoped" must reach 🤞 (tagged "hope") rather than the
        // rabbits that "hop" would have returned.
        let results = search("hoped", limit: 12).map(\.emoji.hexcode)
        let hope = try #require(results.firstIndex(of: "1F91E"))   // 🤞
        if let rabbit = results.firstIndex(of: "1F430") {          // 🐰
            #expect(hope < rabbit)
        }
    }

    @Test func stemsThatAreNotWordsYieldNothing() {
        // "untied" offers unty → unti → untie. None is a term in the corpus
        // (there's no untie emoji), so every candidate is rejected and the
        // picker stays empty rather than showing 📍 via a loose `unty` match.
        #expect(realResults(search("untied")).isEmpty)
    }

    @Test func stemmingOnlyRunsWhenTheQueryFoundNothing() {
        // ":cats" matches 🐱 directly (shortcode "cats"), so the `-s` stem must
        // not run and reshuffle the ranking.
        let direct = search("cats", limit: 12).map(\.emoji.hexcode)
        let bare = search("cat", limit: 12).map(\.emoji.hexcode)
        #expect(!direct.isEmpty)
        #expect(direct != bare)
    }

    @Test func floorSpares2CharQueries() {
        // Short needles score low by construction, so the floor is off below 3
        // characters — the prefix tier carries them instead.
        #expect(!search("wo").isEmpty)
    }

    @Test func tagMatchLabelsWithPrimaryShortcode() throws {
        // A row that matched via the "happy" tag must label itself with the
        // emoji's own primary shortcode (😀 → grinning), not the shared tag
        // word — otherwise the picker shows a run of identical ":happy:" rows.
        let results = realResults(search("happ", limit: 2000))
        let grinning = try #require(results.first { $0.emoji.hexcode == "1F600" })
        #expect(grinning.matchedShortcode == "grinning")
    }

    @Test func shortcodeMatchOutranksTagMatch() throws {
        // For "smile", 😄 (shortcode `smile`) sits in the prefix tier; 😀
        // (grinning) matches "smile" only via a tag. A tag-only match is
        // penalized below every prefix-tier match, so 😄 must rank ahead of 😀.
        // Search the whole corpus (the penalized 😀 doesn't make the default
        // top-12) so both are present to compare.
        let results = realResults(search("smile", limit: 2000))
        let shortcodeIdx = try #require(results.firstIndex { $0.emoji.hexcode == "1F604" })
        let tagOnlyIdx = try #require(results.firstIndex { $0.emoji.hexcode == "1F600" })
        #expect(shortcodeIdx < tagOnlyIdx)
    }
}
