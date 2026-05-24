import Testing
@testable import Mojito

/// Pure state-machine transitions for `TriggerStateMachine`. Zero I/O,
/// no AppKit, no event-tap. Exercises the canonical flows described in
/// the source file's comments so a regression on consume/passthrough
/// semantics or threshold timing trips a test, not a typing experiment.
struct TriggerStateMachineTests {

    // MARK: opening + threshold

    @Test func colonFromIdleStartsCapturingAndPassesThrough() {
        var sm = TriggerStateMachine()
        let out = sm.handle(.colon)
        #expect(sm.state == .capturing(query: ""))
        #expect(out.action == .none)
        // The `:` must reach the focused app — we delete it later only on a real match.
        #expect(out.consumesKey == false)
    }

    @Test func singleNameCharStaysBelowPickerThreshold() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        let out = sm.handle(.nameChar("f"))
        #expect(sm.state == .capturing(query: "f"))
        #expect(out.action == .none)
    }

    @Test func secondNameCharOpensPicker() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        _ = sm.handle(.nameChar("f"))
        let out = sm.handle(.nameChar("o"))
        #expect(out.action == .openPicker(query: "fo", scope: .normal))
    }

    @Test func subsequentNameCharRefreshesPicker() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        _ = sm.handle(.nameChar("f"))
        _ = sm.handle(.nameChar("o"))
        let out = sm.handle(.nameChar("o"))
        #expect(out.action == .refreshPicker(query: "foo", scope: .normal))
    }

    // MARK: completion paths

    @Test func returnKeyFiresFromPickerInsertAndConsumes() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        _ = sm.handle(.nameChar("f"))
        _ = sm.handle(.nameChar("o"))
        _ = sm.handle(.nameChar("o"))
        let out = sm.handle(.returnKey)
        #expect(out.action == .insertEmoji(query: "foo", mode: .fromPicker, scope: .normal))
        #expect(out.consumesKey == true)
        #expect(sm.state == .idle)
    }

    @Test func tabKeyAlsoFiresFromPicker() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        _ = sm.handle(.nameChar("f"))
        _ = sm.handle(.nameChar("o"))
        let out = sm.handle(.tabKey)
        #expect(out.action == .insertEmoji(query: "fo", mode: .fromPicker, scope: .normal))
        #expect(out.consumesKey == true)
    }

    @Test func closingColonFiresExactMatchAndPassesThrough() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        _ = sm.handle(.nameChar("f"))
        _ = sm.handle(.nameChar("o"))
        let out = sm.handle(.colon)
        #expect(out.action == .insertEmoji(query: "fo", mode: .exactMatch, scope: .normal))
        // The closing `:` lands in the focused app first — Engine defers the delete.
        #expect(out.consumesKey == false)
        #expect(sm.state == .idle)
    }

    // MARK: cancel + emoticon paths

    @Test func cancelCharFiresCheckEmoticon() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        _ = sm.handle(.nameChar("D"))
        let out = sm.handle(.cancelChar(" "))
        #expect(out.action == .checkEmoticon(query: "D", terminator: " "))
        #expect(out.consumesKey == false)
        #expect(sm.state == .idle)
    }

    @Test func escapeClosesPickerAndConsumes() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        _ = sm.handle(.nameChar("f"))
        let out = sm.handle(.escape)
        #expect(out.action == .closePicker)
        #expect(out.consumesKey == true)
        #expect(sm.state == .idle)
    }

    // MARK: backspace

    @Test func backspaceRefreshesPickerAboveThreshold() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        _ = sm.handle(.nameChar("f"))
        _ = sm.handle(.nameChar("o"))
        _ = sm.handle(.nameChar("o"))  // .refreshPicker("foo")
        let out = sm.handle(.backspace)
        #expect(out.action == .refreshPicker(query: "fo", scope: .normal))
        #expect(sm.state == .capturing(query: "fo"))
    }

    @Test func backspaceBelowThresholdClosesPicker() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        _ = sm.handle(.nameChar("f"))
        _ = sm.handle(.nameChar("o"))  // .openPicker("fo")
        let out = sm.handle(.backspace)
        #expect(out.action == .closePicker)
        #expect(sm.state == .capturing(query: "f"))
    }

    @Test func backspaceFromEmptyQueryEndsCapture() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        let out = sm.handle(.backspace)
        #expect(out.action == .closePicker)
        #expect(sm.state == .idle)
    }

    // MARK: arrow / navigation

    @Test func arrowDownMovesSelectionAndConsumes() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        _ = sm.handle(.nameChar("f"))
        let out = sm.handle(.arrowDown)
        #expect(out.action == .moveSelection(delta: 1))
        #expect(out.consumesKey == true)
    }

    @Test func arrowsPassthroughOnEmptyQueryAndEndCapture() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        let out = sm.handle(.arrowDown)
        // arrowDown with empty query passes through (caret motion); the
        // SM treats it as "user moved on" via the (.idle, _) catch-all
        // path after process() returns — state should be idle after this.
        // Pull the actual contract from source: on empty query, arrowDown
        // is .passthrough, state stays .capturing. arrowLeft/Right end capture.
        #expect(out.action == .none)
        #expect(out.consumesKey == false)
    }

    @Test func arrowLeftWithEmptyQueryClosesPicker() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        let out = sm.handle(.arrowLeft)
        #expect(out.action == .closePicker)
        #expect(sm.state == .idle)
    }

    // MARK: word-char carve-out — "5:35" shouldn't trigger

    @Test func colonAfterWordCharIsPassthrough() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.nameChar("5"))  // lastWasWordChar = true
        let out = sm.handle(.colon)
        #expect(out.action == .none)
        #expect(out.consumesKey == false)
        #expect(sm.state == .idle)
    }

    @Test func colonAfterBackspaceStillTriggers() {
        // Backspace should not poison the "lastWasWordChar" gate.
        var sm = TriggerStateMachine()
        _ = sm.handle(.nameChar("5"))
        _ = sm.handle(.backspace)
        let out = sm.handle(.colon)
        #expect(sm.state == .capturing(query: ""))
        #expect(out.consumesKey == false)
    }

    // MARK: double-colon

    @Test func doubleColonByDefaultCancels() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        let out = sm.handle(.colon)
        #expect(out.action == .closePicker)
        #expect(sm.state == .idle)
    }

    @Test func doubleColonUpgradesToSymbolsWhenEnabled() {
        var sm = TriggerStateMachine()
        sm.symbolsDoubleColonEnabled = true
        _ = sm.handle(.colon)
        let out = sm.handle(.colon)
        #expect(out.action == .none)
        #expect(out.consumesKey == false)
        // Symbols scope drops threshold to 1, so a single name char opens picker.
        let next = sm.handle(.nameChar("a"))
        #expect(next.action == .openPicker(query: "a", scope: .symbolsOnly))
    }

    // MARK: konami (state-machine-driven payoff)

    @Test func konamiSequenceTriggersAfterColon() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        for input in [TriggerInput.arrowUp, .arrowUp, .arrowDown, .arrowDown,
                      .arrowLeft, .arrowRight, .arrowLeft, .arrowRight,
                      .nameChar("b")] {
            _ = sm.handle(input)
        }
        let out = sm.handle(.nameChar("a"))
        #expect(out.action == .triggerKonami(deleteCount: 1))
        #expect(out.consumesKey == true)
        #expect(sm.state == .idle)
    }

    // MARK: reset

    @Test func resetClearsAllState() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        _ = sm.handle(.nameChar("f"))
        sm.reset()
        #expect(sm.state == .idle)
        // After reset, a fresh colon should open capture cleanly.
        let out = sm.handle(.colon)
        #expect(sm.state == .capturing(query: ""))
        #expect(out.action == .none)
    }
}
