import Testing
@testable import Mojito

/// The welcome demo types real queries through the real ranker, so each
/// scripted line has to land on the result it then inserts.
@MainActor
struct WelcomeSceneTests {

    @Test func everySearchedSceneRanksItsResultFirst() {
        for scene in WelcomeScene.script where scene.act != .gifs {
            let top = FuzzyMatcher.search(
                query: scene.query,
                in: EmojiDatabase.shared,
                usage: [:],
                corpus: scene.act == .symbols ? .symbolsOnly : .emojiOnly,
                useFrequencyBoost: false,
                limit: 5
            ).first
            #expect(top?.emoji.character == scene.result, "\(scene.act) \(scene.query) → \(top?.emoji.character ?? "nothing")")
        }
    }

    @Test func gifScenesInsertNoTextAndEveryTileIsBundled() {
        let scenes = WelcomeScene.script.filter { $0.act == .gifs }
        #expect(!scenes.isEmpty)
        for scene in scenes {
            #expect(scene.result.isEmpty)
            #expect(scene.tiles.count == 6)
            for tile in scene.tiles {
                #expect(WelcomeScene.gifURL(tile) != nil, "missing \(tile).gif")
            }
        }
    }

    @Test func everyPartAppearsInTheScript() {
        for act in WelcomeAct.allCases {
            #expect(WelcomeScene.script.contains { $0.act == act })
        }
    }
}
