import Testing
@testable import Mojito

/// Host-pattern matching for URL exclusions. A `*` wildcard matches exactly
/// one subdomain segment (`[^.]+`) and is anchored at both ends, so it can't
/// span dots or match a suffix of a longer host. A pattern without a wildcard
/// matches the domain itself and any subdomain of it (label-boundary suffix),
/// so `google.com` covers `google.com`, `mail.google.com`, and deeper — but
/// not lookalikes like `notgoogle.com`.
struct ExclusionStoreTests {

    @Test func plainPatternMatchesApexAndSubdomains() {
        #expect(ExclusionStore.matches(host: "google.com", pattern: "google.com"))
        #expect(ExclusionStore.matches(host: "www.google.com", pattern: "google.com"))
        #expect(ExclusionStore.matches(host: "mail.google.com", pattern: "google.com"))
        #expect(ExclusionStore.matches(host: "a.b.google.com", pattern: "google.com"))
    }

    @Test func plainPatternRespectsLabelBoundary() {
        // A shared suffix that isn't on a dot boundary must not match.
        #expect(!ExclusionStore.matches(host: "notgoogle.com", pattern: "google.com"))
        // The pattern must be an actual suffix — a longer host that merely
        // contains it isn't excluded.
        #expect(!ExclusionStore.matches(host: "google.com.evil.com", pattern: "google.com"))
    }

    @Test func plainPatternIsNarrowerThanItsSubdomains() {
        // `mail.google.com` still excludes itself and its own subdomains, but
        // not sibling subdomains of the apex.
        #expect(ExclusionStore.matches(host: "mail.google.com", pattern: "mail.google.com"))
        #expect(ExclusionStore.matches(host: "x.mail.google.com", pattern: "mail.google.com"))
        #expect(!ExclusionStore.matches(host: "drive.google.com", pattern: "mail.google.com"))
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
        // `[^.]+` needs at least one char, so the bare apex doesn't match the
        // wildcard form (use the plain `google.com` pattern to cover the apex).
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
