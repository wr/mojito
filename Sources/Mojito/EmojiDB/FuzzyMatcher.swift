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

    /// Tags ~triple the haystack count, so scan them only once the query is
    /// specific enough to be a real concept search. A 1-char needle already
    /// matches almost everything via shortcodes — adding tags there just
    /// doubles the cost of the worst query for no useful results.
    private static let tagMinNeedle = 2

    /// Score bonus for a user-defined alias haystack. Set above the +5.0
    /// frequency-boost cap so an aliased emoji reliably beats even a
    /// heavily-used built-in when the query is the alias term.
    static let aliasBonus = 6.0

    /// Minimum fzy score per needle character for a match to be shown at all.
    ///
    /// Across ~23k haystacks *something* always matches as a scattered
    /// subsequence, so without a floor `:yeet:` returns 🐞 (y‑e‑e‑t threaded
    /// through "lady beetle") and `:lfg:` returns 🥬. An empty picker is the
    /// honest answer there — the user keeps typing instead of reading junk.
    ///
    /// The value is a tolerance dial, not a clean separator: the two
    /// populations overlap, because a one-character typo costs roughly what a
    /// junk subsequence scores. Measured over the corpus, `roket` → 🚀 lands
    /// at 0.78 and `sml` → 😄 at 0.62, while junk mostly sits below 0.60.
    /// Anything above ~0.65 starts eating typos, which are far more common
    /// than the junk-only queries the floor exists to catch — hence a
    /// deliberately permissive cut that clears ~90% of the noise and keeps
    /// every typo that was reachable at all.
    private static let relevanceFloor = 0.60

    /// Below this the floor is off. Short needles score low by construction
    /// (fewer characters to earn consecutive bonuses) and are driven by the
    /// prefix tier anyway.
    private static let floorMinNeedle = 3

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

        let scanTags = needle.count >= tagMinNeedle

        let pool: [IndexedEmoji]
        switch corpus {
        case .emojiOnly:
            pool = database.indexed
        case .emojiAndSymbols:
            // A symbol an alias targets already lives in `database.indexed`, so
            // drop it from the appended sweep — otherwise it's scored (and
            // rendered) twice, colliding on hexcode in the picker's ForEach.
            let promoted = database.aliasedSymbolHexcodes
            let symbols = promoted.isEmpty
                ? SymbolsCorpus.entries
                : SymbolsCorpus.entries.filter { !promoted.contains($0.emoji.hexcode) }
            pool = database.indexed + symbols
        case .symbolsOnly:
            pool = SymbolsCorpus.entries
        }

        var trimmed = rankedResults(
            needle: needle,
            pool: pool,
            usage: usage,
            useFrequencyBoost: useFrequencyBoost,
            scanTags: scanTags,
            limit: limit
        )

        // Only when the query as typed found nothing: fzy rejects a needle
        // longer than its haystack, so `:ghosted:` can't reach the `ghost`
        // keyword until the suffix comes off. Gated on empty so a query that
        // already works keeps its exact ranking and pays nothing.
        //
        // A candidate has to be a real term in the corpus before it's searched.
        // Stemming guesses several spellings and can't know which is a word, so
        // without the check the first guess wins on any fuzzy hit at all —
        // `movies` → `movy` finds 🎑 (m‑o‑v‑y inside "moon_viewing_ceremony")
        // and shadows `movie` → 🎥 behind it.
        if trimmed.isEmpty {
            for stem in acceptedStems(for: needle, in: pool) {
                trimmed = rankedResults(
                    needle: stem,
                    pool: pool,
                    usage: usage,
                    useFrequencyBoost: useFrequencyBoost,
                    scanTags: stem.count >= tagMinNeedle,
                    limit: limit
                )
                if !trimmed.isEmpty { break }
            }
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

    /// Stem candidates worth searching, best first.
    ///
    /// Keeps only spellings that exist here, then prefers the one retaining
    /// most of what the user typed. Both matter, and for different reasons:
    /// without the corpus check `movies` → `movy` matches 🎑 by accident and
    /// shadows `movie`; without the length preference `hoping` → `hop` is a
    /// real term that shadows `hope`, and `caring` → `car` shadows `care`.
    ///
    /// Ties keep the stemmer's own order, which is why this sorts on a
    /// (length, position) key rather than calling the non-stable `sort`.
    static func acceptedStems(for needle: [Character], in pool: [IndexedEmoji]) -> [[Character]] {
        QueryStemmer.stems(of: needle)
            .enumerated()
            .filter { isCorpusTerm($0.element, in: pool) }
            .sorted { lhs, rhs in
                lhs.element.count != rhs.element.count
                    ? lhs.element.count > rhs.element.count
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Whether `stem` starts some haystack in `pool` — i.e. whether it's a real
    /// term here rather than a spelling the stemmer invented. Plain character
    /// compares, no DP, so it's far cheaper than the fzy pass it gates.
    static func isCorpusTerm(_ stem: [Character], in pool: [IndexedEmoji]) -> Bool {
        for indexed in pool {
            for haystack in indexed.haystacks where haystack.chars.starts(with: stem) {
                return true
            }
        }
        return false
    }

    /// The scoring core: rank a haystack pool against `needle` and return the
    /// top `limit` rows. Split out from `search` so the ranking (including the
    /// alias bonus) is testable with a synthetic pool, without the easter-egg
    /// splicing that `search` layers on top.
    static func rankedResults(
        needle: [Character],
        pool: [IndexedEmoji],
        usage: [String: Int],
        useFrequencyBoost: Bool,
        scanTags: Bool,
        limit: Int
    ) -> [ScoredEmoji] {
        // Internal carrier so the sort can rank by (isPrefix, score, isTag)
        // without baking a magic tier offset into a single Int.
        struct Candidate {
            let emoji: Emoji
            let display: String
            let isPrefix: Bool
            let isTag: Bool
            let score: Double
        }
        var results: [Candidate] = []
        results.reserveCapacity(64)

        let floor = needle.count >= floorMinNeedle
            ? relevanceFloor * Double(needle.count)
            : -Double.infinity

        for indexed in pool {
            var bestScore: Double = -.infinity
            var bestDisplay: String?
            var bestIsTag = false
            var bestUnbonused: Double = -.infinity
            var prefixBestScore: Double = -.infinity
            var prefixBestDisplay: String?
            var prefixBestUnbonused: Double = -.infinity
            for haystack in indexed.haystacks {
                if haystack.isTag && !scanTags { continue }
                guard let base = FzyScorer.score(needle: needle, haystack: haystack.chars) else { continue }
                // A user alias gets a fixed lift so the aliased emoji wins its
                // alias term over built-ins that merely prefix-match it.
                let raw = haystack.isAlias ? base + aliasBonus : base
                // Tags never join the prefix tier — a keyword starting with the
                // query shouldn't outrank a real shortcode. Within the
                // non-prefix tier they compete on fzy relevance, so an exact
                // tag match ("happy") beats a loose shortcode subsequence
                // ("happ" scattered through "handicapped"); isTag is only a
                // tiebreak (see the sort below).
                if !haystack.isTag, haystack.chars.starts(with: needle) {
                    if raw > prefixBestScore {
                        prefixBestScore = raw
                        prefixBestDisplay = haystack.display
                        prefixBestUnbonused = base
                    }
                } else if raw > bestScore {
                    bestScore = raw
                    bestDisplay = haystack.display
                    bestIsTag = haystack.isTag
                    bestUnbonused = base
                }
            }

            // Prefer a prefix-matching haystack's display so the highlight
            // sits at the start of the visible shortcode.
            let isPrefix = prefixBestDisplay != nil
            let display: String
            let baseScore: Double
            let matchedIsTag: Bool
            let unbonusedScore: Double
            if let prefixBestDisplay {
                display = prefixBestDisplay
                baseScore = prefixBestScore
                matchedIsTag = false
                unbonusedScore = prefixBestUnbonused
            } else if let bestDisplay {
                display = bestDisplay
                baseScore = bestScore
                matchedIsTag = bestIsTag
                unbonusedScore = bestUnbonused
            } else {
                continue
            }

            // Measured on the raw fzy score: the alias bonus is a ranking lift,
            // not a relevance override, so an alias term still has to actually
            // resemble the query. Otherwise defining any alias would restore the
            // junk subsequence matches the floor exists to remove. Checked
            // before the frequency boost too, so usage can't rescue junk either.
            if unbonusedScore < floor { continue }

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
                isTag: matchedIsTag,
                score: finalScore
            ))
        }

        // Prefix-tier first, then by relevance, then shortcodes over tags at
        // equal score, then stable emoji order.
        results.sort { lhs, rhs in
            if lhs.isPrefix != rhs.isPrefix { return lhs.isPrefix }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.isTag != rhs.isTag { return !lhs.isTag }
            return lhs.emoji.order < rhs.emoji.order
        }
        return results.prefix(limit).map {
            // A tag match drives ranking but isn't a typable shortcode, and many
            // emoji share one keyword — labelling the row with the tag yields a
            // run of identical ":happy:" rows. Show the emoji's own primary
            // shortcode instead so rows stay distinct and canonical.
            ScoredEmoji(
                emoji: $0.emoji,
                matchedShortcode: $0.isTag ? $0.emoji.primaryShortcode : $0.display,
                isPrefix: $0.isPrefix
            )
        }
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
