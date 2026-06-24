import Foundation

struct ScoredEmoji {
    let emoji: Emoji
    let matchedShortcode: String
    /// True when `matchedShortcode` is a real shortcode/label starting with the
    /// query (the prefix tier) — not a penalized tag match. The egg-hint
    /// placement reads this; a tag display can start with the query yet not be
    /// a prefix-tier match.
    let isPrefix: Bool

    init(emoji: Emoji, matchedShortcode: String, isPrefix: Bool = false) {
        self.emoji = emoji
        self.matchedShortcode = matchedShortcode
        self.isPrefix = isPrefix
    }
}

/// Built lazily so apps that never enable Symbols don't pay for it.
@MainActor
private enum SymbolsCorpus {
    static let entries: [IndexedEmoji] = SymbolsDatabase.indexed()
}

/// Set by Engine from symbol prefs + state-machine scope.
enum SearchCorpus {
    case emojiOnly          // `:foo` with symbols off, OR symbols on + double-colon required
    case emojiAndSymbols    // `:foo` with symbols on + double-colon NOT required
    case symbolsOnly        // `::foo` (only when symbols on + double-colon required)
}

struct FuzzyMatcher {
    // Opaque sentinel hexcodes — the only ids referenced elsewhere.
    // Trigger keywords live exclusively as SHA-256 hashes in `EggIndex`.
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
    static let k15Hex          = "k15"
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
    static let k35Hex     = "k35"
    static let k49Hex     = "k49"
    static let k50Hex     = "k50"
    /// Fires from the state machine, not the picker — no `EggIndex` entry.
    static let k99Hex       = "k99"
    /// Below this we skip the hash lookup, so short prefixes don't surface
    /// a discovery hint.
    private static let specialMinPrefix = 2

    /// Tag (keyword) haystacks are scored, then knocked down by this much so a
    /// shortcode/label match for the same query always outranks a tag-only
    /// match. Big enough to clear a full consecutive match (1.0/char) for the
    /// short shortcodes that dominate the corpus; tags still surface when
    /// nothing better matches (`:meditation` → 🧘).
    private static let tagScorePenalty: Double = -6.0
    /// Tags ~triple the haystack count, so scan them only once the query is
    /// specific enough to be a real concept search. A 1-char needle already
    /// matches almost everything via shortcodes — adding tags there just
    /// doubles the cost of the worst query for no useful results.
    private static let tagMinNeedle = 2

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
        k15Hex:           PinnedRow(hexcode: k15Hex,           character: "🛸", label: "???",      order: 86),
        k16Hex:      PinnedRow(hexcode: k16Hex,      character: "🍞", label: "???",      order: 86),
        k17Hex:           PinnedRow(hexcode: k17Hex,           character: "💿", label: "???",      order: 85),
        k19Hex:          PinnedRow(hexcode: k19Hex,          character: "🟦", label: "???",      order: 84),
        k20Hex:         PinnedRow(hexcode: k20Hex,         character: "🐍", label: "???",      order: 83),
        k21Hex: PinnedRow(hexcode: k21Hex, character: "☢️", label: "???",      order: 82),
        k22Hex:         PinnedRow(hexcode: k22Hex,         character: "🦵", label: "???",      order: 81),
        k23Hex:          PinnedRow(hexcode: k23Hex,          character: "🎉", label: "???",      order: 80),
        k24Hex:            PinnedRow(hexcode: k24Hex,            character: "🪟", label: "???",      order: 79),
        k25Hex:     PinnedRow(hexcode: k25Hex,     character: "🃏", label: "???",      order: 78),
        k27Hex:      PinnedRow(hexcode: k27Hex,      character: "🎤", label: "???",      order: 76),
        k29Hex:           PinnedRow(hexcode: k29Hex,           character: "📺", label: "???",      order: 74),
        k30Hex:        PinnedRow(hexcode: k30Hex,        character: "🥬", label: "???",      order: 73),
        k35Hex:        PinnedRow(hexcode: k35Hex,        character: "🚋", label: "???",      order: 72),
        k49Hex:        PinnedRow(hexcode: k49Hex,        character: "🟩", label: "???",      order: 71),
        k50Hex:        PinnedRow(hexcode: k50Hex,        character: "💽", label: "???",      order: 70),
    ]

    /// Every pinned row renders with the rainbow gradient. (Used to mark
    /// only the named/spoiler-light ones, but the gradient is the visual
    /// "this is special" cue we want on all hidden picks.)
    static var rainbowHexcodes: Set<String> { pinnedHexcodes }

    static let pinnedHexcodes: Set<String> = Set(pinnedRows.keys)

    /// Top `limit` results by fzy score. Frequency boost adds up to +5.0.
    /// All haystacks are precomputed, so the per-keystroke loop never
    /// allocates — no `.lowercased()`, no `[Character]` construction.
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

        // Internal carrier so the sort can rank by (isPrefix, score) without
        // baking a magic tier offset into a single Int.
        struct Candidate {
            let emoji: Emoji
            let display: String
            let isPrefix: Bool
            let score: Double
        }
        var results: [Candidate] = []
        results.reserveCapacity(64)

        let scanTags = needle.count >= tagMinNeedle

        let pool: [IndexedEmoji]
        switch corpus {
        case .emojiOnly:        pool = database.indexed
        case .emojiAndSymbols:  pool = database.indexed + SymbolsCorpus.entries
        case .symbolsOnly:      pool = SymbolsCorpus.entries
        }

        for indexed in pool {
            var bestScore: Double = -.infinity
            var bestDisplay: String?
            var prefixBestScore: Double = -.infinity
            var prefixBestDisplay: String?
            for haystack in indexed.haystacks {
                if haystack.isTag && !scanTags { continue }
                guard let raw = FzyScorer.score(needle: needle, haystack: haystack.chars) else { continue }
                // Tags never join the prefix tier (a keyword starting with the
                // query shouldn't outrank a real shortcode) and take a penalty.
                if !haystack.isTag, haystack.chars.starts(with: needle) {
                    if raw > prefixBestScore {
                        prefixBestScore = raw
                        prefixBestDisplay = haystack.display
                    }
                } else {
                    let score = haystack.isTag ? raw + tagScorePenalty : raw
                    if score > bestScore {
                        bestScore = score
                        bestDisplay = haystack.display
                    }
                }
            }

            // Prefer a prefix-matching haystack's display so the highlight
            // sits at the start of the visible shortcode.
            let isPrefix = prefixBestDisplay != nil
            let display: String
            let baseScore: Double
            if let prefixBestDisplay {
                display = prefixBestDisplay
                baseScore = prefixBestScore
            } else if let bestDisplay {
                display = bestDisplay
                baseScore = bestScore
            } else {
                continue
            }

            var finalScore = baseScore
            if useFrequencyBoost, let count = usage[indexed.emoji.hexcode], count > 0 {
                // Cap at +5.0 (~ one extra strong-bonus match) so popular
                // emoji can't dominate unrelated queries.
                finalScore += min(5.0, Double(count) * 0.2)
            }

            results.append(Candidate(
                emoji: indexed.emoji,
                display: display,
                isPrefix: isPrefix,
                score: finalScore
            ))
        }

        // Prefix-tier first, then by score, then by stable emoji order.
        results.sort { lhs, rhs in
            if lhs.isPrefix != rhs.isPrefix { return lhs.isPrefix }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.emoji.order < rhs.emoji.order
        }
        var trimmed = results.prefix(limit).map {
            ScoredEmoji(emoji: $0.emoji, matchedShortcode: $0.display, isPrefix: $0.isPrefix)
        }

        let lowercased = query.lowercased()

        // Discovery hint sits just below the top real match — a normal
        // shortcode surfaces the actual emoji first, but the hint stays
        // visible right under it — and only once enough of the trigger is
        // typed. Hash the query against `EggIndex` — no plaintext keywords in
        // source. Skipped for `::symbols`.
        var specialRow: ScoredEmoji?
        if corpus != .symbolsOnly,
           EasterEggTracker.eggsEnabled,
           lowercased.count >= specialMinPrefix,
           let hexcode = EggIndex.id(forPrefix: lowercased),
           let row = pinnedRows[hexcode] {
            // Reveal the trigger keyword once the user has discovered the egg —
            // a row stuck on "???" after discovery is just dead weight in the
            // picker.
            var label = row.label
            if label == "???",
               let egg = EasterEgg(rawValue: hexcode),
               EasterEggTracker.isDiscovered(egg) {
                label = egg.pickerLabel
            }
            specialRow = makeSpecialRow(
                hexcode: row.hexcode,
                character: row.character,
                label: label,
                order: row.order
            )
        }

        guard let specialRow else {
            return Array(trimmed.prefix(limit))
        }
        // Rank the hint among the real matches by how well they fit the query,
        // so a genuine match always wins but loose subsequence matches don't:
        //   • right after its lookalike emoji (same glyph), if one matched; else
        //   • right after the last prefix-tier match (shortcode starts with the
        //     query); else
        //   • at the top, when nothing real actually starts with the query.
        let real = Array(trimmed.prefix(max(0, limit - 1)))
        guard !real.isEmpty else { return [specialRow] }
        let insertAt: Int
        if let twin = real.firstIndex(where: { $0.emoji.character == specialRow.emoji.character }) {
            insertAt = twin + 1
        } else if let lastPrefix = real.lastIndex(where: { $0.isPrefix }) {
            insertAt = lastPrefix + 1
        } else {
            insertAt = 0
        }
        var output = real
        output.insert(specialRow, at: insertAt)
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
        return ScoredEmoji(emoji: emoji, matchedShortcode: label)
    }
}
