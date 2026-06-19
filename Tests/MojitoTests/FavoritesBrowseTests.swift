import Testing
import Foundation
@testable import Mojito

/// State-machine behavior for the favorites pill + in-panel browser (W-295).
/// The pill only claims navigation keys once `emptyPickerActive` is set (the
/// Engine flips it after the show), so a `:` followed by a fast keystroke
/// never hijacks the keyboard.
struct TriggerStateMachineBrowseTests {

    @Test func bareColonStaysInert() {
        var sm = TriggerStateMachine()  // no trigger char set
        let out = sm.handle(.colon)
        #expect(out.action == .none)
        #expect(sm.state == .capturing(query: ""))
    }

    @Test func triggerCharOpensPillAndSwallowsIt() {
        var sm = TriggerStateMachine()
        sm.quickAccessTrigger = "?"
        let colon = sm.handle(.colon)
        #expect(colon.action == .none)
        let q = sm.handle(.cancelChar("?"))
        #expect(q.action == .openPicker(query: "", scope: .normal))
        #expect(q.consumesKey == true)
        #expect(sm.state == .capturing(query: ""))
    }

    @Test func customTriggerCharOpensPill() {
        var sm = TriggerStateMachine()
        sm.quickAccessTrigger = ";"
        _ = sm.handle(.colon)
        let semi = sm.handle(.cancelChar(";"))
        #expect(semi.action == .openPicker(query: "", scope: .normal))
        #expect(semi.consumesKey == true)
    }

    @Test func questionMarkIsLiteralWhenTriggerOff() {
        var sm = TriggerStateMachine()  // no trigger char
        _ = sm.handle(.colon)
        let q = sm.handle(.cancelChar("?"))
        #expect(q.action == .checkEmoticon(query: "", terminator: "?"))
    }

    @Test func arrowsPassThroughUntilPillVisible() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        let down = sm.handle(.arrowDown)
        #expect(down.action == .none)
        #expect(down.consumesKey == false)
    }

    @Test func returnIsLiteralUntilPillVisible() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        let ret = sm.handle(.returnKey)
        #expect(ret.action == .closePicker)
        #expect(ret.consumesKey == false)
    }

    @Test func visiblePillNavigatesAndExpands() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        sm.emptyPickerActive = true

        let right = sm.handle(.arrowRight)
        #expect(right.action == .moveSelection(delta: 1))
        #expect(right.consumesKey == true)
        let left = sm.handle(.arrowLeft)
        #expect(left.action == .moveSelection(delta: -1))
        #expect(left.consumesKey == true)

        // Both ↑ and ↓ expand into the full grid.
        let up = sm.handle(.arrowUp)
        #expect(up.action == .expandBrowser)
        #expect(up.consumesKey == true)
        let down = sm.handle(.arrowDown)
        #expect(down.action == .expandBrowser)
        #expect(down.consumesKey == true)
    }

    @Test func pillDigitQuickPicks() {
        var sm = TriggerStateMachine()
        sm.quickAccessTrigger = "?"
        _ = sm.handle(.colon)
        _ = sm.handle(.cancelChar("?"))
        sm.emptyPickerActive = true
        sm.pillEmojiCount = 8
        let three = sm.handle(.nameChar("3"))
        #expect(three.action == .pickIndex(2))  // 1-based digit → 0-based index
        #expect(three.consumesKey == true)
    }

    @Test func pillOutOfRangeDigitStartsSearch() {
        var sm = TriggerStateMachine()
        sm.quickAccessTrigger = "?"
        _ = sm.handle(.colon)
        _ = sm.handle(.cancelChar("?"))
        sm.emptyPickerActive = true
        sm.pillEmojiCount = 2  // only two favorites shown
        let five = sm.handle(.nameChar("5"))
        // Beyond the row count → not a quick-pick; the digit falls through to a
        // normal search instead of being swallowed.
        #expect(five.action == .closePicker)
        #expect(sm.state == .capturing(query: "5"))
    }

    @Test func pillLetterStillStartsSearch() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        sm.emptyPickerActive = true
        let out = sm.handle(.nameChar("a"))
        #expect(out.action == .closePicker)  // a non-digit dismisses to search
        #expect(sm.state == .capturing(query: "a"))
    }

    @Test func questionPillEscapeRestoresQuestionMark() {
        var sm = TriggerStateMachine()
        sm.quickAccessTrigger = "?"
        _ = sm.handle(.colon)
        _ = sm.handle(.cancelChar("?"))
        sm.emptyPickerActive = true
        let esc = sm.handle(.escape)
        #expect(esc.action == .closePickerRestoringTrigger("?"))
        #expect(esc.consumesKey == true)
        #expect(sm.state == .idle)
    }

    @Test func pillEscapeIsPlainCloseWhenTriggerOff() {
        var sm = TriggerStateMachine()  // no trigger char → nothing to restore
        _ = sm.handle(.colon)
        sm.emptyPickerActive = true
        let esc = sm.handle(.escape)
        #expect(esc.action == .closePicker)
    }

    @Test func visiblePillReturnInsertsSelected() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        sm.emptyPickerActive = true
        let ret = sm.handle(.returnKey)
        #expect(ret.action == .insertEmoji(query: "", mode: .fromPicker, scope: .normal))
        #expect(ret.consumesKey == true)
        #expect(sm.state == .idle)
    }

    @Test func normalThresholdStillOpensAfterFavoritesDismissal() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        sm.emptyPickerActive = true
        _ = sm.handle(.nameChar("s"))
        let out = sm.handle(.nameChar("o"))
        #expect(out.action == .openPicker(query: "so", scope: .normal))
    }

    @Test func arrowSideKeysEndCaptureWhenPillNotVisible() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        let left = sm.handle(.arrowLeft)
        #expect(left.action == .closePicker)
        #expect(left.consumesKey == false)
        #expect(sm.state == .idle)
    }

    @Test func resetClearsEmptyPickerFlag() {
        var sm = TriggerStateMachine()
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
        #expect(c.consumesKey == true)
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
struct QuickAccessStoreTests {
    private func makeStore() -> QuickAccessStore {
        let suite = UserDefaults(suiteName: "mojito.tests.quickaccess.\(UUID().uuidString)")!
        return QuickAccessStore(defaults: suite)
    }

    @Test func startsAllAuto() {
        let store = makeStore()
        #expect(store.slots.count == QuickAccessStore.slotCount)
        #expect(store.slots.allSatisfy { $0 == nil })
        #expect(!store.hasPins)
    }

    @Test func pinResetAndDedup() {
        let store = makeStore()
        store.pin("1F600", at: 0)
        #expect(store.slots[0] == "1F600")
        #expect(store.hasPins)
        // Re-pinning the same glyph elsewhere clears the old slot.
        store.pin("1F600", at: 3)
        #expect(store.slots[0] == nil)
        #expect(store.slots[3] == "1F600")
        store.reset(at: 3)
        #expect(store.slots[3] == nil)
        #expect(!store.hasPins)
    }

    @Test func resetAllClearsPins() {
        let store = makeStore()
        store.pin("A", at: 1)
        store.pin("B", at: 2)
        store.resetAll()
        #expect(store.slots.allSatisfy { $0 == nil })
    }

    @Test func persistsAcrossInstances() {
        let suiteName = "mojito.tests.quickaccess.persist.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        let first = QuickAccessStore(defaults: suite)
        first.pin("2764", at: 2)
        let second = QuickAccessStore(defaults: suite)
        #expect(second.slots[2] == "2764")
        #expect(second.slots.filter { $0 != nil }.count == 1)
    }

    @Test func resolvedKeepsPinAtSlotAndAutoFillsMostUsed() {
        let db = EmojiDatabase.shared
        guard db.all.count >= 3 else { return }
        let store = makeStore()
        let pin = db.all[0].hexcode
        let a = db.all[1].hexcode
        let b = db.all[2].hexcode
        store.pin(pin, at: 1)
        // slot 0 auto → top most-used (b:10), slot 1 pinned, slot 2 auto → next (a:3)
        let resolved = QuickAccess.resolved(store: store, database: db, usage: [a: 3, b: 10]).map(\.hexcode)
        #expect(resolved.count >= 3)
        #expect(resolved[0] == b)
        #expect(resolved[1] == pin)
        #expect(resolved[2] == a)
    }

    @Test func resolvedExcludesPinnedFromAutoFill() {
        let db = EmojiDatabase.shared
        guard db.all.count >= 1 else { return }
        let store = makeStore()
        let x = db.all[0].hexcode
        store.pin(x, at: 0)
        // x is also the most-used — it must not also appear in an auto slot.
        let resolved = QuickAccess.resolved(store: store, database: db, usage: [x: 99]).map(\.hexcode)
        #expect(resolved.filter { $0 == x }.count == 1)
    }

    @Test func resolvedIsDeterministic() {
        let db = EmojiDatabase.shared
        guard db.all.count >= 2 else { return }
        let store = makeStore()
        let x = db.all[0].hexcode
        let y = db.all[1].hexcode
        let usage = [x: 5, y: 5]
        let first = QuickAccess.resolved(store: store, database: db, usage: usage).map(\.hexcode)
        let second = QuickAccess.resolved(store: store, database: db, usage: usage).map(\.hexcode)
        #expect(first == second)
        #expect(Array(first.prefix(2)) == [min(x, y), max(x, y)])
    }
}
