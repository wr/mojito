import Testing
@testable import Mojito

/// `QueryStemmer` produces *candidate* spellings, not one canonical stem — the
/// corpus decides which candidate exists. So these assert that the right
/// spelling is offered, not that it's the only one or that it comes first.
struct QueryStemmerTests {

    private func stems(_ query: String) -> [String] {
        QueryStemmer.stems(of: Array(query)).map { String($0) }
    }

    @Test(arguments: [
        ("ghosted", "ghost"),
        ("deployed", "deploy"),
        ("launching", "launch"),
        ("blocking", "block"),
        ("hearts", "heart"),
        ("wishes", "wish"),
    ])
    func offersThePlainStem(query: String, stem: String) {
        #expect(stems(query).contains(stem))
    }

    @Test(arguments: [
        ("parties", "party"),
        ("carried", "carry"),
    ])
    func restoresYForIesAndIed(query: String, stem: String) {
        #expect(stems(query).contains(stem))
    }

    @Test(arguments: [
        ("celebrating", "celebrate"),
        ("smiled", "smile"),
    ])
    func restoresADroppedE(query: String, stem: String) {
        #expect(stems(query).contains(stem))
    }

    @Test(arguments: [
        ("shipping", "ship"),
        ("shipped", "ship"),
    ])
    func undoesConsonantDoubling(query: String, stem: String) {
        #expect(stems(query).contains(stem))
    }

    @Test func keepsTheLosslessStemAheadOfTheLossyOne() throws {
        // "pressed" → "press" (real) must be offered before "pres" (junk from
        // the doubled-consonant rule), since the caller stops at the first hit.
        let candidates = stems("pressed")
        let press = try #require(candidates.firstIndex(of: "press"))
        if let pres = candidates.firstIndex(of: "pres") {
            #expect(press < pres)
        }
    }

    @Test(arguments: ["press", "glass", "grass"])
    func neverStripsSFromADoubleS(query: String) {
        #expect(!stems(query).contains(String(query.dropLast())))
    }

    @Test(arguments: ["ghost", "heart", "smile", "rocket", "cat"])
    func uninflectedQueryYieldsNothing(query: String) {
        // Nothing to strip — the fallback should never fire on these.
        #expect(stems(query).isEmpty)
    }

    @Test(arguments: ["is", "as", "ing", "ed", "es"])
    func tooShortToStem(query: String) {
        // A 2–3 char query would stem to something meaninglessly generic.
        #expect(stems(query).isEmpty)
    }

    @Test func neverEmitsAStemBelowThreeCharacters() {
        for query in ["ties", "toes", "pies", "dyes", "axes", "owed", "ring"] {
            #expect(stems(query).allSatisfy { $0.count >= 3 })
        }
    }
}
