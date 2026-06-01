import Testing
@testable import Mojito

/// Ambient emoticons need no leading `:`. Keys are full literal sequences,
/// so case variants are distinct, and the fire timing depends on whether
/// the sequence is punctuation-led (fire on completion) or letter/number-
/// led (wait for a terminator so it can't eat into prose).
struct AmbientEmoticonTableTests {

    @Test func knownSequencesMapToEmoji() {
        #expect(AmbientEmoticonTable.emoji(for: "<3") == "❤️")
        #expect(AmbientEmoticonTable.emoji(for: "</3") == "💔")
        #expect(AmbientEmoticonTable.emoji(for: "XD") == "😆")
        #expect(AmbientEmoticonTable.emoji(for: "xD") == "😆")
        #expect(AmbientEmoticonTable.emoji(for: ">:)") == "😈")
        #expect(AmbientEmoticonTable.emoji(for: "B)") == "😎")
    }

    @Test func arrowsMapToUnicodeGlyphs() {
        #expect(AmbientEmoticonTable.emoji(for: "->") == "→")
        #expect(AmbientEmoticonTable.emoji(for: "<-") == "←")
        #expect(AmbientEmoticonTable.emoji(for: "<->") == "↔")
        #expect(AmbientEmoticonTable.emoji(for: "=>") == "⇒")
        #expect(AmbientEmoticonTable.emoji(for: "<=") == "⇐")
        #expect(AmbientEmoticonTable.emoji(for: "<=>") == "⇔")
    }

    @Test func arrowKeysAreJustThePunctuationArrows() {
        // Derived from the map — only keys built solely from arrow punctuation.
        #expect(AmbientEmoticonTable.arrowKeys == ["->", "<-", "<->", "=>", "<=", "<=>"])
        // Hearts / smileys are NOT arrows even though they're punctuation-led.
        #expect(!AmbientEmoticonTable.arrowKeys.contains("<3"))
        #expect(!AmbientEmoticonTable.arrowKeys.contains("</3"))
        #expect(!AmbientEmoticonTable.arrowKeys.contains(">:)"))
    }

    @Test func arrowSuffixPullsTrailingArrowOutOfABuffer() {
        // The whole point of the fix: find the arrow at the end of `Foo->`.
        #expect(AmbientEmoticonTable.arrowSuffix(of: "Foo->") == "->")
        #expect(AmbientEmoticonTable.arrowSuffix(of: "Foo<->") == "<->")  // longest wins
        #expect(AmbientEmoticonTable.arrowSuffix(of: "Foo<=") == "<=")
        // No trailing arrow → nil (incomplete `<`, or plain prose).
        #expect(AmbientEmoticonTable.arrowSuffix(of: "Foo<") == nil)
        #expect(AmbientEmoticonTable.arrowSuffix(of: "hello") == nil)
        // A non-arrow punctuation emoticon is not pulled as a suffix.
        #expect(AmbientEmoticonTable.arrowSuffix(of: "Hi<3") == nil)
    }

    @Test func hasLongerArrowDefersOnlyTheExtendableArrows() {
        #expect(AmbientEmoticonTable.hasLongerArrow(extending: "<-"))   // → <->
        #expect(AmbientEmoticonTable.hasLongerArrow(extending: "<="))   // → <=>
        #expect(!AmbientEmoticonTable.hasLongerArrow(extending: "->"))
        #expect(!AmbientEmoticonTable.hasLongerArrow(extending: "=>"))
        #expect(!AmbientEmoticonTable.hasLongerArrow(extending: "<->"))
        #expect(!AmbientEmoticonTable.hasLongerArrow(extending: "<=>"))
    }

    @Test func caseVariantsAreSeparateKeys() {
        // "XD"/"xD" are registered; "Xd"/"xd" are not.
        #expect(AmbientEmoticonTable.emoji(for: "Xd") == nil)
        #expect(AmbientEmoticonTable.emoji(for: "xd") == nil)
    }

    @Test func unknownOrEmptyReturnsNil() {
        #expect(AmbientEmoticonTable.emoji(for: "hello") == nil)
        #expect(AmbientEmoticonTable.emoji(for: "") == nil)
    }

    @Test func punctuationLedFiresImmediately() {
        #expect(AmbientEmoticonTable.shouldFireImmediately("<3"))
        #expect(AmbientEmoticonTable.shouldFireImmediately("</3"))
        #expect(AmbientEmoticonTable.shouldFireImmediately(">:)"))
        #expect(AmbientEmoticonTable.shouldFireImmediately("->"))
        #expect(AmbientEmoticonTable.shouldFireImmediately("<-"))
        #expect(AmbientEmoticonTable.shouldFireImmediately("<->"))
        #expect(AmbientEmoticonTable.shouldFireImmediately("=>"))
        #expect(AmbientEmoticonTable.shouldFireImmediately("<=>"))
    }

    @Test func hasLongerMatchFindsTableExtensions() {
        // `<-` is in the table and so is `<->` — the state machine uses
        // this to defer firing `←` while `↔` is still reachable.
        #expect(AmbientEmoticonTable.hasLongerMatch(for: "<-"))
        // `>` has both `>:)` and `>:(` as longer entries.
        #expect(AmbientEmoticonTable.hasLongerMatch(for: ">"))
        // `<=` isn't itself in the table but extends to `<=>`.
        #expect(AmbientEmoticonTable.hasLongerMatch(for: "<="))
    }

    @Test func hasLongerMatchReturnsFalseForTerminalEntries() {
        // No table key strictly extends these.
        #expect(!AmbientEmoticonTable.hasLongerMatch(for: "<->"))
        #expect(!AmbientEmoticonTable.hasLongerMatch(for: "<=>"))
        #expect(!AmbientEmoticonTable.hasLongerMatch(for: "->"))
        #expect(!AmbientEmoticonTable.hasLongerMatch(for: "=>"))
        #expect(!AmbientEmoticonTable.hasLongerMatch(for: ""))
    }

    @Test func letterOrNumberLedWaitsForTerminator() {
        // Would otherwise eat into "XDog" / "Bobby".
        #expect(!AmbientEmoticonTable.shouldFireImmediately("XD"))
        #expect(!AmbientEmoticonTable.shouldFireImmediately("B)"))
    }

    @Test func incompleteSequenceDoesNotFire() {
        #expect(!AmbientEmoticonTable.shouldFireImmediately("<"))
        #expect(!AmbientEmoticonTable.shouldFireImmediately(">"))
        #expect(!AmbientEmoticonTable.shouldFireImmediately(""))
    }

    @Test func colonContinuationPrefixesCoversAngleBracket() {
        // `>` must be allowed to continue with `:` so `>:)` isn't hijacked
        // by colon-capture.
        #expect(AmbientEmoticonTable.colonContinuationPrefixes.contains(">"))
    }
}
