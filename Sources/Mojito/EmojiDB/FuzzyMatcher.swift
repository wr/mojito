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
    static let k01Hex    = "k01"
    static let k02Hex       = "k02"
    static let k03Hex         = "k03"
    static let k04Hex     = "k04"
    static let k05Hex        = "k05"
    static let k06Hex       = "k06"
    static let k07Hex       = "k07"
    static let k08Hex       = "k08"
    static let k09Hex      = "k09"
    static let k10Hex         = "k10"
    static let k11Hex       = "k11"
    static let k12Hex    = "k12"
    static let k13Hex      = "k13"
    static let k14Hex    = "k14"
    static let k16Hex     = "k16"
    static let k17Hex          = "k17"
    static let k19Hex         = "k19"
    static let k20Hex        = "k20"
    static let k21Hex = "k21"
    static let k22Hex        = "k22"
    static let k23Hex         = "k23"
    static let k24Hex           = "k24"
    static let k25Hex    = "k25"
    static let k27Hex     = "k27"
    static let k29Hex          = "k29"
    static let k30Hex       = "k30"
    /// Konami code payoff — fires from the state machine, not the picker,
    /// so it has no entry in `EggIndex` and isn't typeable.
    static let k99Hex       = "k99"
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
        k01Hex:     PinnedRow(hexcode: k01Hex,     character: "🎁", label: "???",      order: 100),
        k02Hex:        PinnedRow(hexcode: k02Hex,        character: "🎲", label: "random",   order: 99),
        k03Hex:          PinnedRow(hexcode: k03Hex,          character: "🐮", label: "???",      order: 98),
        k04Hex:      PinnedRow(hexcode: k04Hex,      character: "🎊", label: EggStrings.k04Label, order: 97),
        k05Hex:         PinnedRow(hexcode: k05Hex,         character: "🏳️‍🌈", label: EggStrings.k05Label,    order: 96),
        k06Hex:        PinnedRow(hexcode: k06Hex,        character: "🔔", label: "???",      order: 95),
        k07Hex:        PinnedRow(hexcode: k07Hex,        character: "💾", label: "???",      order: 94),
        k08Hex:        PinnedRow(hexcode: k08Hex,        character: "📞", label: "???",      order: 93),
        k09Hex:       PinnedRow(hexcode: k09Hex,       character: "🎬", label: "???",      order: 92),
        k10Hex:          PinnedRow(hexcode: k10Hex,          character: "❄️", label: "???",      order: 91),
        k11Hex:        PinnedRow(hexcode: k11Hex,        character: "🟢", label: "???",      order: 90),
        k12Hex:     PinnedRow(hexcode: k12Hex,     character: "🎆", label: "???",      order: 89),
        k13Hex:       PinnedRow(hexcode: k13Hex,       character: "🐉", label: "???",      order: 88),
        k14Hex:     PinnedRow(hexcode: k14Hex,     character: "🏝️", label: "???",      order: 87),
        k16Hex:      PinnedRow(hexcode: k16Hex,      character: "🍞", label: "???",      order: 86),
        k17Hex:           PinnedRow(hexcode: k17Hex,           character: "💿", label: "???",      order: 85),
        k19Hex:          PinnedRow(hexcode: k19Hex,          character: "💙", label: "???",      order: 84),
        k20Hex:         PinnedRow(hexcode: k20Hex,         character: "🐍", label: "???",      order: 83),
        k21Hex: PinnedRow(hexcode: k21Hex, character: "☢️", label: "???",      order: 82),
        k22Hex:         PinnedRow(hexcode: k22Hex,         character: "🦵", label: "???",      order: 81),
        k23Hex:          PinnedRow(hexcode: k23Hex,          character: "🎉", label: "???",      order: 80),
        k24Hex:            PinnedRow(hexcode: k24Hex,            character: "🪟", label: "???",      order: 79),
        k25Hex:     PinnedRow(hexcode: k25Hex,     character: "🃏", label: "???",      order: 78),
        k27Hex:      PinnedRow(hexcode: k27Hex,      character: "🎤", label: "???",      order: 76),
        k29Hex:           PinnedRow(hexcode: k29Hex,           character: "📺", label: "???",      order: 74),
        k30Hex:        PinnedRow(hexcode: k30Hex,        character: "🥬", label: "???",      order: 73),
    ]

    /// Hexcodes whose picker rows render with the playful rainbow gradient.
    /// Only the v0.1 named rows (random/confetti/pride). Everything else
    /// pinned shows the `???` mystery label.
    static let rainbowHexcodes: Set<String> = [
        k02Hex, k04Hex, k05Hex
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
