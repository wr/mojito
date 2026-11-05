import Testing
@testable import Mojito

/// Kaomoji ride the Symbols trigger: searchable and typable as `::shrug::`,
/// but kept out of the symbol index the browser grid and Quick Access read.
struct KaomojiTableTests {
    private func top(_ query: String) -> ScoredEmoji? {
        FuzzyMatcher.rankedResults(
            needle: Array(query), pool: SymbolsDatabase.searchable, usage: [:],
            useFrequencyBoost: false, scanTags: query.count >= 2, limit: 5
        ).first
    }

    @Test func issueExamplesAreFindableByName() {
        let expected: [(query: String, kaomoji: String)] = [
            ("shrug", "¯\\_(ツ)_/¯"),
            ("tableflip", "(╯°□°)╯︵ ┻━┻"),
            ("flip", "(╯°□°)╯"),
            ("wide_eyes", "(⊙_⊙)"),
            ("cute", ">⩊<"),
            ("lenny", "( ͡° ͜ʖ ͡°)"),
        ]
        for (query, kaomoji) in expected {
            #expect(top(query)?.emoji.character == kaomoji, "expected \(kaomoji) for \"\(query)\"")
        }
    }

    @Test func exactShortcodeIsTheTopRowLikeTheClosingDelimiterNeeds() {
        // `::shrug::` inserts the top-5 hit whose label equals the query.
        let hit = top("shrug")
        #expect(hit?.matchedShortcode == "shrug")
        #expect(hit?.emoji.isKaomoji == true)
    }

    @Test func tagsFindFacesByMood() {
        let hits = FuzzyMatcher.rankedResults(
            needle: Array("angry"), pool: KaomojiTable.all, usage: [:],
            useFrequencyBoost: false, scanTags: true, limit: 12
        )
        #expect(hits.count >= 3)
        // A tag match labels the row with the face's own shortcode.
        #expect(hits.allSatisfy { $0.emoji.shortcodes.contains($0.matchedShortcode) })
    }

    @Test func shortcodesAreTypableAndUnique() {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
        var seen = Set<String>()
        for entry in KaomojiTable.entries {
            #expect(!entry.shortcodes.isEmpty)
            for code in entry.shortcodes {
                #expect(code.allSatisfy { allowed.contains($0) }, "\(code) isn't a typable shortcode")
                #expect(seen.insert(code).inserted, "\(code) is used twice")
            }
        }
    }

    @Test func facesAreUnique() {
        let faces = KaomojiTable.entries.map(\.kaomoji)
        #expect(Set(faces).count == faces.count)
    }

    @Test func everyFaceFitsOneSyntheticKeyEvent() {
        // `TextInserter` posts the whole string in one key event, whose
        // Unicode payload tops out at 20 UTF-16 units.
        for entry in KaomojiTable.entries {
            #expect(entry.kaomoji.utf16.count <= 20, "\(entry.kaomoji) is too long to insert")
        }
    }

    @Test func hexcodesFileKaomojiAsSymbols() {
        for indexed in KaomojiTable.all {
            #expect(indexed.emoji.hexcode.hasPrefix("SYM_"))
            #expect(indexed.emoji.isKaomoji)
            #expect(!indexed.emoji.supportsSkinTone)
        }
        let hexcodes = KaomojiTable.all.map(\.emoji.hexcode)
        #expect(Set(hexcodes).count == hexcodes.count)
    }

    @Test func stayOutOfTheSymbolIndex() {
        // `all` / `byHexcode` back the browser grid and Quick Access, where a
        // wide face can't fit a cell.
        #expect(!SymbolsDatabase.all.contains { $0.emoji.isKaomoji })
        #expect(!SymbolsDatabase.byHexcode.keys.contains { $0.hasPrefix(KaomojiTable.hexcodePrefix) })
        #expect(SymbolsDatabase.searchable.count == SymbolsDatabase.all.count + KaomojiTable.all.count)
    }

    @Test func plainSymbolsAreNotKaomoji() {
        let cmd = SymbolsDatabase.all.first { $0.emoji.character == "⌘" }
        #expect(cmd?.emoji.isKaomoji == false)
    }
}
