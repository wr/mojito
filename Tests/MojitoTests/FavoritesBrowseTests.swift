import Testing
import Foundation
@testable import Mojito

/// State-machine behavior for the favorites pill + in-panel browser (W-295).
/// The pill only claims navigation keys once `emptyPickerActive` is set (the
/// Engine flips it after the show), so a `:` followed by a fast keystroke
/// never hijacks the keyboard.
struct TriggerStateMachineBrowseTests {

    @Test func bareColonOpensPillWhenColonTrigger() {
        var sm = TriggerStateMachine()
        sm.favoritesTrigger = .colon
        let out = sm.handle(.colon)
        #expect(sm.state == .capturing(query: ""))
        #expect(out.action == .openPicker(query: "", scope: .normal))
        #expect(out.consumesKey == false)
    }

    @Test func bareColonStaysInertWhenOff() {
        var sm = TriggerStateMachine()  // favoritesTrigger defaults .off
        let out = sm.handle(.colon)
        #expect(out.action == .none)
        #expect(sm.state == .capturing(query: ""))
    }

    @Test func questionMarkOpensPillAndSwallowsItWhenQuestionTrigger() {
        var sm = TriggerStateMachine()
        sm.favoritesTrigger = .question
        let colon = sm.handle(.colon)
        #expect(colon.action == .none)  // bare `:` is inert in `:?` mode
        let q = sm.handle(.cancelChar("?"))
        #expect(q.action == .openPicker(query: "", scope: .normal))
        #expect(q.consumesKey == true)  // the `?` is swallowed
        #expect(sm.state == .capturing(query: ""))
    }

    @Test func questionMarkIsLiteralWhenColonTrigger() {
        var sm = TriggerStateMachine()
        sm.favoritesTrigger = .colon
        _ = sm.handle(.colon)
        let q = sm.handle(.cancelChar("?"))
        #expect(q.action == .checkEmoticon(query: "", terminator: "?"))
    }

    @Test func arrowsPassThroughUntilPillVisible() {
        var sm = TriggerStateMachine()
        sm.favoritesTrigger = .colon
        _ = sm.handle(.colon)
        let down = sm.handle(.arrowDown)
        #expect(down.action == .none)
        #expect(down.consumesKey == false)
    }

    @Test func returnIsLiteralUntilPillVisible() {
        var sm = TriggerStateMachine()
        sm.favoritesTrigger = .colon
        _ = sm.handle(.colon)
        let ret = sm.handle(.returnKey)
        #expect(ret.action == .closePicker)
        #expect(ret.consumesKey == false)
    }

    @Test func visiblePillNavigatesAndExpands() {
        var sm = TriggerStateMachine()
        sm.favoritesTrigger = .colon
        _ = sm.handle(.colon)
        sm.emptyPickerActive = true

        let right = sm.handle(.arrowRight)
        #expect(right.action == .moveSelection(delta: 1))
        #expect(right.consumesKey == true)
        let left = sm.handle(.arrowLeft)
        #expect(left.action == .moveSelection(delta: -1))
        #expect(left.consumesKey == true)

        let up = sm.handle(.arrowUp)
        #expect(up.action == .none)
        #expect(up.consumesKey == true)
        let down = sm.handle(.arrowDown)
        #expect(down.action == .expandBrowser)
        #expect(down.consumesKey == true)
    }

    @Test func visiblePillReturnInsertsSelected() {
        var sm = TriggerStateMachine()
        sm.favoritesTrigger = .colon
        _ = sm.handle(.colon)
        sm.emptyPickerActive = true
        let ret = sm.handle(.returnKey)
        #expect(ret.action == .insertEmoji(query: "", mode: .fromPicker, scope: .normal))
        #expect(ret.consumesKey == true)
        #expect(sm.state == .idle)
    }

    @Test func typingDismissesVisiblePill() {
        var sm = TriggerStateMachine()
        sm.favoritesTrigger = .colon
        _ = sm.handle(.colon)
        sm.emptyPickerActive = true
        let out = sm.handle(.nameChar("s"))
        #expect(out.action == .closePicker)
        #expect(sm.state == .capturing(query: "s"))
        #expect(sm.emptyPickerActive == false)
    }

    @Test func normalThresholdStillOpensAfterFavoritesDismissal() {
        var sm = TriggerStateMachine()
        sm.favoritesTrigger = .colon
        _ = sm.handle(.colon)
        sm.emptyPickerActive = true
        _ = sm.handle(.nameChar("s"))
        let out = sm.handle(.nameChar("o"))
        #expect(out.action == .openPicker(query: "so", scope: .normal))
    }

    @Test func arrowSideKeysEndCaptureWhenPillNotVisible() {
        var sm = TriggerStateMachine()
        sm.favoritesTrigger = .colon
        _ = sm.handle(.colon)
        let left = sm.handle(.arrowLeft)
        #expect(left.action == .closePicker)
        #expect(left.consumesKey == false)
        #expect(sm.state == .idle)
    }

    @Test func resetClearsEmptyPickerFlag() {
        var sm = TriggerStateMachine()
        sm.favoritesTrigger = .colon
        _ = sm.handle(.colon)
        sm.emptyPickerActive = true
        sm.reset()
        #expect(sm.emptyPickerActive == false)
        #expect(sm.state == .idle)
    }

    // MARK: in-panel browser routing

    @Test func browsingRoutesTypingNavAndPick() {
        var sm = TriggerStateMachine()
        sm.enterBrowsing(query: "")
        #expect(sm.state == .browsing(query: ""))

        let c = sm.handle(.nameChar("c"))
        #expect(c.action == .refreshBrowser(query: "c"))
        #expect(c.consumesKey == true)  // typing never leaks to the focused app
        _ = sm.handle(.nameChar("a"))
        let space = sm.handle(.cancelChar(" "))
        #expect(space.action == .refreshBrowser(query: "ca "))

        let down = sm.handle(.arrowDown)
        #expect(down.action == .moveBrowser(direction: .down))
        #expect(down.consumesKey == true)

        let pick = sm.handle(.returnKey)
        #expect(pick.action == .pickBrowser)
        #expect(pick.consumesKey == true)
        #expect(sm.state == .idle)
    }

    @Test func browsingBackspacePastEmptyCloses() {
        var sm = TriggerStateMachine()
        sm.enterBrowsing(query: "")
        let close = sm.handle(.backspace)
        #expect(close.action == .closeBrowser)
        #expect(sm.state == .idle)
    }

    @Test func browsingEscapeCloses() {
        var sm = TriggerStateMachine()
        sm.enterBrowsing(query: "ab")
        let esc = sm.handle(.escape)
        #expect(esc.action == .closeBrowser)
        #expect(esc.consumesKey == true)
        #expect(sm.state == .idle)
    }
}

@MainActor
struct FavoritesStoreTests {
    private func makeStore() -> FavoritesStore {
        let suite = UserDefaults(suiteName: "mojito.tests.favorites.\(UUID().uuidString)")!
        return FavoritesStore(defaults: suite)
    }

    @Test func addDedupesAndToggleRemoves() {
        let store = makeStore()
        #expect(store.hexcodes.isEmpty)
        store.add("1F600")
        store.add("1F600")
        #expect(store.hexcodes == ["1F600"])
        store.toggle("1F601")
        #expect(store.hexcodes == ["1F600", "1F601"])
        store.toggle("1F600")
        #expect(store.hexcodes == ["1F601"])
        #expect(store.isFavorite("1F601"))
        #expect(!store.isFavorite("1F600"))
    }

    @Test func moveMatchesSwiftUIContract() {
        let store = makeStore()
        ["A", "B", "C", "D"].forEach { store.add($0) }
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(store.hexcodes == ["B", "C", "A", "D"])
    }

    @Test func persistsAcrossInstances() {
        let suiteName = "mojito.tests.favorites.persist.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        let first = FavoritesStore(defaults: suite)
        first.add("2764")
        first.add("1F44D")
        let second = FavoritesStore(defaults: suite)
        #expect(second.hexcodes == ["2764", "1F44D"])
    }
}
