import Testing
@testable import Mojito

/// The ZWJ-sequence insertion logic is the load-bearing case called out
/// in CLAUDE.md: modifier MUST land after the first scalar so
/// `🧔` + `‍♀️` + dark renders as 🧔🏿‍♀️, not 🧔‍♀️🏿.
struct SkinToneTests {

    @Test func defaultIsIdentity() {
        #expect(SkinTone.default.apply(to: "👋") == "👋")
        #expect(SkinTone.default.apply(to: "🧔\u{200D}♀\u{FE0F}") == "🧔\u{200D}♀\u{FE0F}")
    }

    @Test func darkAppendsModifierToSingleScalarEmoji() {
        let result = SkinTone.dark.apply(to: "👋")
        let scalars = Array(result.unicodeScalars).map { $0.value }
        #expect(scalars == [0x1F44B, 0x1F3FF])
    }

    @Test func darkInsertsModifierAfterFirstScalarOfZWJSequence() {
        // "🧔‍♀️" = U+1F9D4 ZWJ U+2640 FE0F. With dark tone the modifier
        // (U+1F3FF) must land after 1F9D4, BEFORE the ZWJ.
        let woman = "\u{1F9D4}\u{200D}\u{2640}\u{FE0F}"
        let result = SkinTone.dark.apply(to: woman)
        let scalars = Array(result.unicodeScalars).map { $0.value }
        #expect(scalars == [0x1F9D4, 0x1F3FF, 0x200D, 0x2640, 0xFE0F])
    }

    @Test(arguments: [
        (SkinTone.light, 0x1F3FB as UInt32),
        (.mediumLight,   0x1F3FC),
        (.medium,        0x1F3FD),
        (.mediumDark,    0x1F3FE),
        (.dark,          0x1F3FF),
    ])
    func modifierCodepointsAreCorrect(_ tone: SkinTone, _ expected: UInt32) {
        let scalars = Array(tone.modifier.unicodeScalars).map { $0.value }
        #expect(scalars == [expected])
    }

    @Test func defaultModifierIsEmpty() {
        #expect(SkinTone.default.modifier.isEmpty)
    }

    @Test func allCasesHaveDisplayName() {
        for tone in SkinTone.allCases {
            #expect(!tone.displayName.isEmpty)
        }
    }

    @Test func swatchEmojiUsesVulcanSalute() {
        // Vulcan salute base is U+1F596 — that scalar is in every swatch,
        // followed by the appropriate modifier (or nothing for default).
        for tone in SkinTone.allCases {
            let first = tone.swatchEmoji.unicodeScalars.first?.value
            #expect(first == 0x1F596)
        }
    }

    @Test func emptyStringIsReturnedUnchanged() {
        #expect(SkinTone.dark.apply(to: "") == "")
    }
}
