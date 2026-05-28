import Testing
@testable import Mojito

/// Host-pattern matching for URL exclusions. A `*` wildcard matches exactly
/// one subdomain segment (`[^.]+`) and is anchored at both ends, so it can't
/// span dots or match a suffix of a longer host. Patterns without a wildcard
/// are compared by exact equality.
struct ExclusionStoreTests {

    @Test func plainPatternMatchesByEquality() {
        #expect(ExclusionStore.matches(host: "mail.google.com", pattern: "mail.google.com"))
        #expect(!ExclusionStore.matches(host: "mail.google.com", pattern: "google.com"))
    }

    @Test func wildcardMatchesOneSegment() {
        #expect(ExclusionStore.matches(host: "mail.google.com", pattern: "*.google.com"))
        #expect(ExclusionStore.matches(host: "drive.google.com", pattern: "*.google.com"))
    }

    @Test func wildcardDoesNotSpanDots() {
        // `*` is a single segment — it must not match across `a.b`.
        #expect(!ExclusionStore.matches(host: "a.mail.google.com", pattern: "*.google.com"))
    }

    @Test func wildcardRequiresANonEmptySegment() {
        // `[^.]+` needs at least one char, so the bare apex doesn't match.
        #expect(!ExclusionStore.matches(host: "google.com", pattern: "*.google.com"))
    }

    @Test func wildcardIsAnchoredAtBothEnds() {
        #expect(!ExclusionStore.matches(host: "mail.google.com.evil.com", pattern: "*.google.com"))
        #expect(!ExclusionStore.matches(host: "x.google.com", pattern: "*.google.co"))
    }

    @Test func dotsInPatternAreLiteralNotRegexWildcards() {
        // The `.` must be escaped — "*Xgoogleycom" must not match "*.google.com".
        #expect(!ExclusionStore.matches(host: "mailXgoogleYcom", pattern: "*.google.com"))
    }

    @Test func compiledGlobOnlyForWildcardPatterns() {
        #expect(ExclusionStore.compiledGlob(for: "google.com") == nil)
        #expect(ExclusionStore.compiledGlob(for: "*.google.com") != nil)
    }
}
