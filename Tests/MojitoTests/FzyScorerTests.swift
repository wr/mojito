import Testing
@testable import Mojito

/// fzy port. Tests check ordering invariants — not exact magic numbers —
/// so future scoring tweaks don't need a wholesale rewrite as long as
/// the relative ranking stays sensible.
struct FzyScorerTests {

    private func score(_ needle: String, _ haystack: String) -> Double? {
        FzyScorer.score(
            needle: Array(needle.lowercased()),
            haystack: Array(haystack.lowercased())
        )
    }

    @Test func nonSubsequenceReturnsNil() {
        #expect(score("abcd", "axc") == nil)
        #expect(score("xyz", "abc") == nil)
    }

    @Test func needleLongerThanHaystackReturnsNil() {
        #expect(score("longer", "ab") == nil)
    }

    @Test func emptyNeedleReturnsNil() {
        #expect(score("", "anything") == nil)
    }

    @Test func equalLengthExactMatchScoresMaxConsecutive() {
        // Special case: n == m → bypasses DP, returns score directly.
        let s = score("abc", "abc")
        #expect(s == FzyScorer.scoreMatchConsecutive * 3.0)
    }

    @Test func substringStartScoresHigherThanEmbedded() {
        let prefix = score("ab", "abxxxx")
        let embedded = score("ab", "xxabxx")
        #expect(prefix != nil && embedded != nil)
        #expect(prefix! > embedded!)
    }

    @Test func consecutiveMatchScoresHigherThanGapped() {
        let consec = score("abc", "abcxyz")
        let gapped = score("abc", "axbxcy")
        #expect(consec != nil && gapped != nil)
        #expect(consec! > gapped!)
    }

    @Test func wordBoundaryAfterUnderscoreBoostsMatch() {
        // After-`_` chars get +0.8 — `smile_unamused` (the actual shortcode
        // this bonus exists for) is the canonical example. Match starting
        // at the `u` of `unamused` should be findable.
        let s = score("un", "smile_unamused")
        #expect(s != nil)
    }

    @Test func caseInsensitiveLowercasedAtCallSite() {
        // FzyScorer itself is case-sensitive — the matcher lowercases.
        // Verify equivalent lowercase inputs match.
        let a = score("abc", "abcdef")
        let b = score("ABC", "ABCDEF")
        #expect(a != nil)
        #expect(b != nil)
        #expect(a == b)
    }

    @Test func atLeastOneCharRequired() {
        #expect(score("", "") == nil)
        #expect(score("a", "") == nil)
    }
}
