import Testing
@testable import Mojito

/// `EmoticonTable.match` is `query + terminator`-first, then `query`-only.
/// The `consumesTerminator` bit tells the Engine whether the terminator
/// char is part of the emoticon (`:)` consumes `)`) or just a delimiter
/// (`:D ` does not consume the space).
struct EmoticonTableTests {

    @Test func punctuationTailConsumesTerminator() {
        let m = EmoticonTable.match(query: "", terminator: ")")
        #expect(m?.emoji == "🙂")
        #expect(m?.consumesTerminator == true)
    }

    @Test func letterEmoticonDoesNotConsumeSpaceDelimiter() {
        let m = EmoticonTable.match(query: "D", terminator: " ")
        #expect(m?.emoji == "😃")
        #expect(m?.consumesTerminator == false)
    }

    @Test func dashedPunctuationTailMatches() {
        // ":-)" arrives as query "-" + terminator ")".
        let m = EmoticonTable.match(query: "-", terminator: ")")
        #expect(m?.emoji == "🙂")
        #expect(m?.consumesTerminator == true)
    }

    @Test func dashedLetterMatchesAsQuery() {
        // ":-D " arrives as query "-D" + terminator " ".
        let m = EmoticonTable.match(query: "-D", terminator: " ")
        #expect(m?.emoji == "😃")
        #expect(m?.consumesTerminator == false)
    }

    @Test func cryingAndLaughingApostropheVariants() {
        let crying = EmoticonTable.match(query: "'", terminator: "(")
        #expect(crying?.emoji == "😢")
        #expect(crying?.consumesTerminator == true)

        let joy = EmoticonTable.match(query: "'", terminator: ")")
        #expect(joy?.emoji == "😂")
        #expect(joy?.consumesTerminator == true)
    }

    @Test func emptyQueryWithUnknownTerminatorReturnsNil() {
        #expect(EmoticonTable.match(query: "", terminator: "z") == nil)
    }

    @Test func unknownQueryReturnsNil() {
        #expect(EmoticonTable.match(query: "xyz", terminator: "!") == nil)
    }

    @Test func combinedKeyTakesPriorityOverQueryAlone() {
        // ")" is in the map (as ":)" with terminator ")"), but ":D" is
        // also in the map under "D" alone. Make sure query "D" +
        // terminator ")" finds "D)" first if it existed, else falls back
        // to "D". The table has no "D)" entry, so we expect the fallback.
        let m = EmoticonTable.match(query: "D", terminator: ")")
        #expect(m?.emoji == "😃")
        #expect(m?.consumesTerminator == false)
    }
}
