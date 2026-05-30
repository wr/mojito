import Testing
import Foundation
@testable import Mojito

/// State-machine behavior for the bare-`:` favorites picker (W-295). The
/// key invariant: the picker only claims ↑↓ / Return once `emptyPickerActive`
/// is set (the Engine flips it after the debounced show), so a `:` followed
/// by a fast keystroke never hijacks navigation.
struct TriggerStateMachineBrowseTests {

    @Test func bareColonOpensFavoritesPickerWhenEnabled() {
        var sm = TriggerStateMachine()
        sm.browseOnColonEnabled = true
        let out = sm.handle(.colon)
        #expect(sm.state == .capturing(query: ""))
        #expect(out.action == .openPicker(query: "", scope: .normal))
        #expect(out.consumesKey == false)
    }

    @Test func bareColonStaysInertWhenDisabled() {
        var sm = TriggerStateMachine()  // browseOnColonEnabled defaults false
        let out = sm.handle(.colon)
        #expect(out.action == .none)
        #expect(sm.state == .capturing(query: ""))
    }

    @Test func arrowsPassThroughUntilPickerVisible() {
        // Armed (enabled) but not yet shown — ↓ must move the caret, not the
        // (invisible) picker selection.
        var sm = TriggerStateMachine()
        sm.browseOnColonEnabled = true
        _ = sm.handle(.colon)
        let down = sm.handle(.arrowDown)
        #expect(down.action == .none)
        #expect(down.consumesKey == false)
    }

    @Test func returnIsLiteralUntilPickerVisible() {
        var sm = TriggerStateMachine()
        sm.browseOnColonEnabled = true
        _ = sm.handle(.colon)
        let ret = sm.handle(.returnKey)
        #expect(ret.action == .closePicker)
        #expect(ret.consumesKey == false)  // `:`+Return passes through as a literal
    }

    @Test func visiblePickerOwnsArrowsAndReturn() {
        var sm = TriggerStateMachine()
        sm.browseOnColonEnabled = true
        _ = sm.handle(.colon)
        sm.emptyPickerActive = true  // Engine flips this after the show

        let down = sm.handle(.arrowDown)
        #expect(down.action == .moveSelection(delta: 1))
        #expect(down.consumesKey == true)

        let up = sm.handle(.arrowUp)
        #expect(up.action == .moveSelection(delta: -1))
        #expect(up.consumesKey == true)

        // The pill is horizontal — ←/→ navigate it too.
        let right = sm.handle(.arrowRight)
        #expect(right.action == .moveSelection(delta: 1))
        #expect(right.consumesKey == true)
        let left = sm.handle(.arrowLeft)
        #expect(left.action == .moveSelection(delta: -1))
        #expect(left.consumesKey == true)

        let ret = sm.handle(.returnKey)
        #expect(ret.action == .insertEmoji(query: "", mode: .fromPicker, scope: .normal))
        #expect(ret.consumesKey == true)
        #expect(sm.state == .idle)
    }

    @Test func typingDismissesVisiblePicker() {
        var sm = TriggerStateMachine()
        sm.browseOnColonEnabled = true
        _ = sm.handle(.colon)
        sm.emptyPickerActive = true
        let out = sm.handle(.nameChar("s"))
        #expect(out.action == .closePicker)
        #expect(sm.state == .capturing(query: "s"))
        #expect(sm.emptyPickerActive == false)
    }

    @Test func normalThresholdStillOpensAfterFavoritesDismissal() {
        var sm = TriggerStateMachine()
        sm.browseOnColonEnabled = true
        _ = sm.handle(.colon)
        sm.emptyPickerActive = true
        _ = sm.handle(.nameChar("s"))           // dismisses favorites
        let out = sm.handle(.nameChar("o"))     // crosses the 2-char threshold
        #expect(out.action == .openPicker(query: "so", scope: .normal))
    }

    @Test func arrowSideKeysEndCaptureWhenPillNotVisible() {
        // Without the pill up, ← on a bare `:` still escapes the colon.
        var sm = TriggerStateMachine()
        sm.browseOnColonEnabled = true
        _ = sm.handle(.colon)
        let left = sm.handle(.arrowLeft)
        #expect(left.action == .closePicker)
        #expect(left.consumesKey == false)
        #expect(sm.state == .idle)
    }

    @Test func resetClearsEmptyPickerFlag() {
        var sm = TriggerStateMachine()
        sm.browseOnColonEnabled = true
        _ = sm.handle(.colon)
        sm.emptyPickerActive = true
        sm.reset()
        #expect(sm.emptyPickerActive == false)
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
        store.add("1F600")  // no dupe
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
