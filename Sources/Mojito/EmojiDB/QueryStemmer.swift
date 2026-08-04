import Foundation

/// Strips common English inflections so an inflected query can reach an
/// uninflected keyword.
///
/// `FzyScorer` rejects a needle longer than its haystack, so `:ghosted:` can
/// never match the `ghost` / `ghosting` keywords no matter how scoring is
/// tuned — the match dies before the DP runs. Trimming the suffix is the only
/// way through.
///
/// Deliberately cruder than a real stemmer (Porter, Snowball). It runs only as
/// a fallback when the raw query found nothing, so a wrong guess costs an empty
/// picker staying empty — never a worse result for a query that already works.
/// That asymmetry is what lets the rules be this loose.
enum QueryStemmer {

    /// Below this a stem is too generic to mean anything.
    private static let minStem = 3

    /// Candidate stems for `needle`, most likely first; empty when no rule
    /// applies. Callers try each in order and stop at the first with results.
    ///
    /// Several spellings are offered at once on purpose: `-ing` alone can't
    /// tell `shipping` (undo a doubled consonant) from `celebrating` (restore a
    /// dropped `e`) from `blocking` (plain trim), so all three go out and the
    /// corpus decides which one exists.
    static func stems(of needle: [Character]) -> [[Character]] {
        var out: [[Character]] = []

        func add(_ candidate: [Character]) {
            guard candidate.count >= minStem, !out.contains(candidate) else { return }
            out.append(candidate)
        }

        /// `shipping` → `shipp` → `ship`. Doubled consonants only, so `pressed`
        /// yields `press` before the lossy `pres`.
        func undoubled(_ stem: [Character]) -> [Character]? {
            guard let last = stem.last,
                  stem.count > minStem,
                  last == stem[stem.count - 2],
                  !"aeiou".contains(last)
            else { return nil }
            return Array(stem.dropLast())
        }

        func hasSuffix(_ chars: [Character]) -> Bool {
            needle.count > chars.count && needle.suffix(chars.count).elementsEqual(chars)
        }

        func trim(_ suffix: String, restoringE: Bool = false) {
            let chars = Array(suffix)
            guard hasSuffix(chars) else { return }
            let stem = Array(needle.dropLast(chars.count))
            add(stem)
            // `celebrat` is nothing; `celebrate` is the word.
            if restoringE { add(stem + ["e"]) }
            if let shorter = undoubled(stem) { add(shorter) }
        }

        /// `parties` → `party`. A constructed spelling, not a substring of what
        /// was typed.
        func restoreY() {
            add(Array(needle.dropLast(3)) + ["y"])
        }

        // `-ies` is reliably the plural of a `-y` noun, so it outranks the
        // generic trims: `skies` is sky + s, never ski + es (that's `skis`).
        if hasSuffix(["i", "e", "s"]) { restoreY() }

        trim("ing", restoringE: true)
        trim("ed", restoringE: true)
        trim("es")
        // `press` is not `pres`.
        if !hasSuffix(["s", "s"]) { trim("s") }

        // `-ied` carries no such guarantee — `carried` is carry + ied but
        // `skied` is ski + ed — so it goes last and only wins when the plain
        // trim didn't land on a real word. Callers rank corpus-exact candidates
        // above prefix-only ones, so `carry` still beats `carri` from here.
        if hasSuffix(["i", "e", "d"]) { restoreY() }

        return out
    }
}
