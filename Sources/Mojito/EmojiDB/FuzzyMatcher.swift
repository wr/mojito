import Foundation

struct ScoredEmoji {
    let emoji: Emoji
    let matchedShortcode: String
    let score: Int
}

/// One-time-built indexed corpus for the experimental Symbols set. Built
/// lazily on first read so apps that never enable Symbols never pay for it.
@MainActor
private enum SymbolsCorpus {
    static let entries: [IndexedEmoji] = SymbolsDatabase.indexed()
}

/// Which corpus FuzzyMatcher should search. Set by Engine based on the user's
/// symbol prefs and the current trigger-state-machine scope.
enum SearchCorpus {
    case emojiOnly          // `:foo` with symbols off, OR symbols on + double-colon required
    case emojiAndSymbols    // `:foo` with symbols on + double-colon NOT required
    case symbolsOnly        // `::foo` (only reachable when symbols on + double-colon required)
}

struct FuzzyMatcher {
    // Opaque sentinel hexcodes. These are the only ids referenced anywhere
    // else in the codebase — neither the trigger keywords nor any
    // user-facing names appear here. Plain-text keywords live exclusively
    // as hashes in `EggIndex`.
    //
    // The Swift identifier names stay descriptive so the rest of the code
    // is readable; the *literal values* are what get embedded in the binary.
    static let easterEggHexcode    = "k01"
    static let randomHexcode       = "k02"
    static let moofHexcode         = "k03"
    static let confettiHexcode     = "k04"
    static let prideHexcode        = "k05"
    static let sosumiHexcode       = "k06"
    static let floppyHexcode       = "k07"
    static let dialupHexcode       = "k08"
    static let wilhelmHexcode      = "k09"
    static let snowHexcode         = "k10"
    static let matrixHexcode       = "k11"
    static let fireworksHexcode    = "k12"
    static let trogdorHexcode      = "k13"
    static let dontPanicHexcode    = "k14"
    static let toastersHexcode     = "k16"
    static let dvdHexcode          = "k17"
    static let bsodHexcode         = "k19"
    static let snakeHexcode        = "k20"
    static let thermonuclearHexcode = "k21"
    static let mylegHexcode        = "k22"
    static let tadaHexcode         = "k23"
    static let xpHexcode           = "k24"
    static let solitaireHexcode    = "k25"
    static let rickrollHexcode     = "k27"
    static let crtHexcode          = "k29"
    static let celeryHexcode       = "k30"
    /// Konami code payoff — fires from the state machine, not the picker,
    /// so it has no entry in `EggIndex` and isn't typeable.
    static let konamiHexcode       = "k99"
    /// Minimum query length before a special row surfaces. Below this we
    /// don't even hash — saves a round-trip on every keystroke. Shorter
    /// keywords (any of length 2) match at length 2 instead; `EggIndex`
    /// already encodes that.
    private static let specialMinPrefix = 2

    /// Display data for a pinned row, keyed by opaque id. Keywords live
    /// only in `EggIndex` (as hashes) — nothing here reveals them.
    private struct PinnedRow {
        let hexcode: String
        let character: String
        let label: String
        let order: Int
    }
    private static let pinnedRows: [String: PinnedRow] = [
        easterEggHexcode:     PinnedRow(hexcode: easterEggHexcode,     character: "🎁", label: "???",      order: 100),
        randomHexcode:        PinnedRow(hexcode: randomHexcode,        character: "🎲", label: "random",   order: 99),
        moofHexcode:          PinnedRow(hexcode: moofHexcode,          character: "🐮", label: "???",      order: 98),
        confettiHexcode:      PinnedRow(hexcode: confettiHexcode,      character: "🎊", label: "confetti", order: 97),
        prideHexcode:         PinnedRow(hexcode: prideHexcode,         character: "🏳️‍🌈", label: "pride",    order: 96),
        sosumiHexcode:        PinnedRow(hexcode: sosumiHexcode,        character: "🔔", label: "???",      order: 95),
        floppyHexcode:        PinnedRow(hexcode: floppyHexcode,        character: "💾", label: "???",      order: 94),
        dialupHexcode:        PinnedRow(hexcode: dialupHexcode,        character: "📞", label: "???",      order: 93),
        wilhelmHexcode:       PinnedRow(hexcode: wilhelmHexcode,       character: "🎬", label: "???",      order: 92),
        snowHexcode:          PinnedRow(hexcode: snowHexcode,          character: "❄️", label: "???",      order: 91),
        matrixHexcode:        PinnedRow(hexcode: matrixHexcode,        character: "🟢", label: "???",      order: 90),
        fireworksHexcode:     PinnedRow(hexcode: fireworksHexcode,     character: "🎆", label: "???",      order: 89),
        trogdorHexcode:       PinnedRow(hexcode: trogdorHexcode,       character: "🐉", label: "???",      order: 88),
        dontPanicHexcode:     PinnedRow(hexcode: dontPanicHexcode,     character: "🏝️", label: "???",      order: 87),
        toastersHexcode:      PinnedRow(hexcode: toastersHexcode,      character: "🍞", label: "???",      order: 86),
        dvdHexcode:           PinnedRow(hexcode: dvdHexcode,           character: "💿", label: "???",      order: 85),
        bsodHexcode:          PinnedRow(hexcode: bsodHexcode,          character: "💙", label: "???",      order: 84),
        snakeHexcode:         PinnedRow(hexcode: snakeHexcode,         character: "🐍", label: "???",      order: 83),
        thermonuclearHexcode: PinnedRow(hexcode: thermonuclearHexcode, character: "☢️", label: "???",      order: 82),
        mylegHexcode:         PinnedRow(hexcode: mylegHexcode,         character: "🦵", label: "???",      order: 81),
        tadaHexcode:          PinnedRow(hexcode: tadaHexcode,          character: "🎉", label: "???",      order: 80),
        xpHexcode:            PinnedRow(hexcode: xpHexcode,            character: "🪟", label: "???",      order: 79),
        solitaireHexcode:     PinnedRow(hexcode: solitaireHexcode,     character: "🃏", label: "???",      order: 78),
        rickrollHexcode:      PinnedRow(hexcode: rickrollHexcode,      character: "🎤", label: "???",      order: 76),
        crtHexcode:           PinnedRow(hexcode: crtHexcode,           character: "📺", label: "???",      order: 74),
        celeryHexcode:        PinnedRow(hexcode: celeryHexcode,        character: "🥬", label: "???",      order: 73),
    ]

    /// Hexcodes whose picker rows render with the playful rainbow gradient.
    /// Only the v0.1 named rows (random/confetti/pride). Everything else
    /// pinned shows the `???` mystery label.
    static let rainbowHexcodes: Set<String> = [
        randomHexcode, confettiHexcode, prideHexcode
    ]

    /// Every pinned-row hexcode (used by PickerView to render the `???`
    /// mystery label for any non-rainbow pinned egg).
    static let pinnedHexcodes: Set<String> = Set(pinnedRows.keys)

    /// Returns the top `limit` emoji ranked by fzy-style fuzzy match against
    /// `query`. Frequency boost (if enabled) adds up to +5.0 to the raw score.
    ///
    /// All haystacks are precomputed at DB load (see `EmojiDatabase.indexed`),
    /// so per-keystroke cost is just the scorer's DP — no string allocation,
    /// no `.lowercased()`, no `[Character]` construction in the hot loop.
    @MainActor
    static func search(
        query: String,
        in database: EmojiDatabase,
        usage: [String: Int],
        corpus: SearchCorpus,
        useFrequencyBoost: Bool,
        limit: Int = 12
    ) -> [ScoredEmoji] {
        let needle = Array(query.lowercased())
        guard !needle.isEmpty else { return [] }

        var results: [ScoredEmoji] = []
        results.reserveCapacity(64)

        let pool: [IndexedEmoji]
        switch corpus {
        case .emojiOnly:        pool = database.indexed
        case .emojiAndSymbols:  pool = database.indexed + SymbolsCorpus.entries
        case .symbolsOnly:      pool = SymbolsCorpus.entries
        }

        for indexed in pool {
            var bestScore: Double = -.infinity
            var bestDisplay: String?
            for haystack in indexed.haystacks {
                guard let score = FzyScorer.score(needle: needle, haystack: haystack.chars) else { continue }
                if score > bestScore {
                    bestScore = score
                    bestDisplay = haystack.display
                }
            }
            guard let bestDisplay else { continue }

            var finalScore = bestScore
            if useFrequencyBoost, let count = usage[indexed.emoji.hexcode], count > 0 {
                // Cap the boost so frequently-used emoji can't dominate
                // unrelated queries — at most +5.0, roughly the strength of
                // one extra strong-bonus match.
                finalScore += min(5.0, Double(count) * 0.2)
            }

            // ScoredEmoji.score is Int for stable ordering elsewhere; multiply
            // by 1000 to preserve the fzy gap penalties (~0.01 increments).
            let intScore = Int(finalScore * 1000)
            results.append(ScoredEmoji(
                emoji: indexed.emoji,
                matchedShortcode: bestDisplay,
                score: intScore
            ))
        }

        results.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.emoji.order < rhs.emoji.order
        }
        var trimmed = Array(results.prefix(limit))

        let lowercased = query.lowercased()

        // Pinned rows at the TOP of results. Keywords aren't stored in
        // source — we hash the typed query and look up against `EggIndex`,
        // which holds every valid prefix as a SHA-256 digest. Skipped in
        // symbols-only mode — `::random` shouldn't roll an emoji.
        var output: [ScoredEmoji] = []
        if corpus != .symbolsOnly,
           lowercased.count >= specialMinPrefix,
           let hexcode = EggIndex.id(forPrefix: lowercased),
           let row = pinnedRows[hexcode] {
            output.append(makeSpecialRow(
                hexcode: row.hexcode,
                character: row.character,
                label: row.label,
                order: row.order
            ))
        }

        // Fill the remaining slots with real fuzzy matches.
        let remainingSlots = max(0, limit - output.count)
        output.append(contentsOf: trimmed.prefix(remainingSlots))
        return output
    }

    private static func makeSpecialRow(hexcode: String, character: String, label: String, order: Int) -> ScoredEmoji {
        let emoji = Emoji(
            hexcode: hexcode,
            character: character,
            label: label,
            shortcodes: [label],
            tags: [],
            group: -1,
            order: order
        )
        return ScoredEmoji(emoji: emoji, matchedShortcode: label, score: order)
    }
}
