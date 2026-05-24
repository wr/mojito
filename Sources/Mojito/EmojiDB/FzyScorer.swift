import Foundation

/// fzy-style fuzzy scorer. Produces a Double for each (needle, haystack) pair
/// such that better matches score higher. Returns nil if needle isn't a
/// subsequence of haystack.
///
/// Adapted from John Hawthorn's fzy: https://github.com/jhawthorn/fzy/blob/master/SCORING.md
///
/// Key bonuses for emoji shortcodes:
///  - Consecutive matches score +1.0 (so "tad" against "tada" beats "tad" against "transgender_flag")
///  - Match-after-`_` scores +0.8 (so "su" against "smile_unamused" boosts the `u` after the underscore)
///  - Gaps in the middle of the match are mildly penalized (so "tu" against "thumbs_up" still wins
///    over "tu" against "stutterer" because the latter has more inner gap).
///
/// Inputs are pre-lowercased Character arrays (random-access, no UTF-8 walks),
/// so the hot loop is tight. Per-call cost on emoji-sized strings: a few µs.
struct FzyScorer {
    static let scoreMin: Double = -.infinity
    static let scoreGapLeading: Double = -0.005
    static let scoreGapTrailing: Double = -0.005
    static let scoreGapInner: Double = -0.01
    static let scoreMatchConsecutive: Double = 1.0
    static let scoreMatchWord: Double = 0.8
    static let scoreMatchSlash: Double = 0.9
    static let scoreMatchDot: Double = 0.6

    /// Returns the best score for matching `needle` within `haystack`, or nil
    /// if no subsequence match exists. Higher scores are better.
    static func score(needle: [Character], haystack: [Character]) -> Double? {
        let n = needle.count
        let m = haystack.count
        guard n > 0, m > 0, n <= m else { return nil }

        // Subsequence rejection — runs in O(m) before we touch the DP arrays.
        var k = 0
        for c in haystack {
            if c == needle[k] {
                k += 1
                if k == n { break }
            }
        }
        guard k == n else { return nil }

        // Exact match shortcut.
        if n == m { return scoreMatchConsecutive * Double(n) }

        let bonus = computeBonuses(haystack: haystack)

        // Rolling two-row DP. D = best score ending at haystack[j] consuming
        // needle[i]. M = best score using haystack[0..j] consuming needle[0..i].
        var dCurr = [Double](repeating: scoreMin, count: m)
        var mCurr = [Double](repeating: scoreMin, count: m)
        var dPrev = [Double](repeating: scoreMin, count: m)
        var mPrev = [Double](repeating: scoreMin, count: m)

        for i in 0..<n {
            var prev = scoreMin
            let gapScore = (i == n - 1) ? scoreGapTrailing : scoreGapInner
            for j in 0..<m {
                if needle[i] == haystack[j] {
                    var s = scoreMin
                    if i == 0 {
                        s = (Double(j) * scoreGapLeading) + bonus[j]
                    } else if j > 0 {
                        s = max(
                            mPrev[j - 1] + bonus[j],
                            dPrev[j - 1] + scoreMatchConsecutive
                        )
                    }
                    dCurr[j] = s
                    mCurr[j] = max(s, prev + gapScore)
                } else {
                    dCurr[j] = scoreMin
                    mCurr[j] = prev + gapScore
                }
                prev = mCurr[j]
            }
            swap(&dCurr, &dPrev)
            swap(&mCurr, &mPrev)
        }
        return mPrev[m - 1]
    }

    private static func computeBonuses(haystack: [Character]) -> [Double] {
        var bonuses = [Double](repeating: 0, count: haystack.count)
        // Treat the implicit prefix as a separator so the first char gets a
        // word-boundary bonus.
        var prev: Character = "/"
        for i in 0..<haystack.count {
            bonuses[i] = bonus(prev: prev, current: haystack[i])
            prev = haystack[i]
        }
        return bonuses
    }

    private static func bonus(prev: Character, current: Character) -> Double {
        if prev == "/" { return scoreMatchSlash }
        if prev == "_" || prev == " " || prev == "-" { return scoreMatchWord }
        if prev == "." { return scoreMatchDot }
        return 0
    }
}
