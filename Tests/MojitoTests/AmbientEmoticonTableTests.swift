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
        #expect(AmbientEmoticonTable.emoji(for: "<=>") == "⇔")
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
