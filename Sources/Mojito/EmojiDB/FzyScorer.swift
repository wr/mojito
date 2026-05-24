import Foundation

/// fzy-style fuzzy scorer. Higher = better; nil if needle isn't a
/// subsequence of haystack. Adapted from John Hawthorn's fzy:
/// https://github.com/jhawthorn/fzy/blob/master/SCORING.md
///
/// Bonuses tuned for emoji shortcodes: consecutive matches (+1.0) boost
/// "tad" → "tada" over "tad" → "transgender_flag"; after-`_` matches
/// (+0.8) boost "su" → "smile_unamused"; inner gaps are mildly penalized.
///
/// Inputs are pre-lowercased `[Character]` (random-access, no UTF-8
/// walks) — per-call cost is a few µs.
struct FzyScorer {
    static let scoreMin: Double = -.infinity
    static let scoreGapLeading: Double = -0.005
    static let scoreGapTrailing: Double = -0.005
    static let scoreGapInner: Double = -0.01
    static let scoreMatchConsecutive: Double = 1.0
    static let scoreMatchWord: Double = 0.8
    static let scoreMatchSlash: Double = 0.9
    static let scoreMatchDot: Double = 0.6

    static func score(needle: [Character], haystack: [Character]) -> Double? {
        let n = needle.count
        let m = haystack.count
        guard n > 0, m > 0, n <= m else { return nil }

        // Subsequence rejection — O(m), runs before the DP arrays allocate.
        var k = 0
        for c in haystack {
            if c == needle[k] {
                k += 1
                if k == n { break }
            }
        }
        guard k == n else { return nil }

        if n == m { return scoreMatchConsecutive * Double(n) }

        let bonus = computeBonuses(haystack: haystack)

        // Two-row DP. D[j] = best score ending at haystack[j];
        // M[j] = best score using haystack[0..j].
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
        // Implicit prefix is a separator so the first char gets a bonus.
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
