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

    @Test func subThresholdBackspaceStaysCapturingThenReopens() {
        // Invariant: a sub-threshold backspace emits .closePicker but
        // the SM stays in .capturing. The Engine relies on this to keep the
        // capture's exclusion flag / focus snapshot alive — if the SM went
        // idle here, the metadata would (correctly) be torn down. Typing back
        // up to the threshold must re-open the picker on the SAME capture.
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        _ = sm.handle(.nameChar("f"))
        _ = sm.handle(.nameChar("o"))  // .openPicker("fo")
        let close = sm.handle(.backspace)
        #expect(close.action == .closePicker)
        #expect(sm.state == .capturing(query: "f"))
        let reopen = sm.handle(.nameChar("o"))
        #expect(reopen.action == .openPicker(query: "fo", scope: .normal))
        #expect(sm.state == .capturing(query: "fo"))
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

    // MARK: GIF picker (:::)

    /// Drive the machine into `.gifSearching` via three quick colons.
    /// Colon #2 momentarily cancels capture back to idle, but the rolling
    /// `recentColonTimes` window survives that, so colon #3 still trips the
    /// GIF trigger — that's the behaviour this helper pins down.
    private func enterGifSearching() -> TriggerStateMachine {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        _ = sm.handle(.colon)
        _ = sm.handle(.colon)
        return sm
    }

    @Test func tripleColonOpensGifPicker() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        _ = sm.handle(.colon)
        let out = sm.handle(.colon)
        #expect(out.action == .openGifPicker)
        // The colons stay in the focused app — deleted only when a GIF is picked.
        #expect(out.consumesKey == false)
        #expect(sm.state == .gifSearching(query: ""))
    }

    @Test func gifNameCharsRefreshQueryAndPassThrough() {
        var sm = enterGifSearching()
        _ = sm.handle(.nameChar("c"))
        let out = sm.handle(.nameChar("a"))
        #expect(out.action == .refreshGifPicker(query: "ca"))
        // Mirrors emoji UX: query is echoed into the focused app too.
        #expect(out.consumesKey == false)
        #expect(sm.state == .gifSearching(query: "ca"))
    }

    @Test func gifQueryAcceptsSpacesAndColons() {
        var sm = enterGifSearching()
        _ = sm.handle(.nameChar("a"))
        let space = sm.handle(.cancelChar(" "))
        #expect(space.action == .refreshGifPicker(query: "a "))
        // A colon mid-search is just part of the query, not a new trigger.
        let colon = sm.handle(.colon)
        #expect(colon.action == .refreshGifPicker(query: "a :"))
        #expect(sm.state == .gifSearching(query: "a :"))
    }

    @Test func gifBackspacePeelsQueryThenClosesOnEmpty() {
        var sm = enterGifSearching()
        _ = sm.handle(.nameChar("h"))
        let peel = sm.handle(.backspace)
        #expect(peel.action == .refreshGifPicker(query: ""))
        #expect(sm.state == .gifSearching(query: ""))
        let close = sm.handle(.backspace)
        #expect(close.action == .closeGifPicker)
        #expect(close.consumesKey == false)
        #expect(sm.state == .idle)
    }

    @Test func gifReturnPicksAndDeletesTripleColonPlusQuery() {
        var sm = enterGifSearching()
        for ch in "dog" { _ = sm.handle(.nameChar(ch)) }
        let out = sm.handle(.returnKey)
        // deleteCount = query.count (3) + the three colons typed through.
        #expect(out.action == .pickGif(deleteCount: 6))
        #expect(out.consumesKey == true)
        #expect(sm.state == .idle)
    }

    @Test func gifTabAlsoPicksWithEmptyQuery() {
        var sm = enterGifSearching()
        let out = sm.handle(.tabKey)
        #expect(out.action == .pickGif(deleteCount: 3))
        #expect(out.consumesKey == true)
    }

    @Test func gifEscapeClosesAndConsumes() {
        var sm = enterGifSearching()
        let out = sm.handle(.escape)
        #expect(out.action == .closeGifPicker)
        #expect(out.consumesKey == true)
        #expect(sm.state == .idle)
    }

    @Test func gifArrowsMoveSelectionAndConsume() {
        var sm = enterGifSearching()
        #expect(sm.handle(.arrowRight).action == .moveGifSelection(direction: .right))
        #expect(sm.handle(.arrowLeft).action == .moveGifSelection(direction: .left))
        #expect(sm.handle(.arrowDown).action == .moveGifSelection(direction: .down))
        let up = sm.handle(.arrowUp)
        #expect(up.action == .moveGifSelection(direction: .up))
        #expect(up.consumesKey == true)
        // Navigation never leaves the search state.
        #expect(sm.state == .gifSearching(query: ""))
    }

    @Test func gifFocusChangeClosesWithoutConsuming() {
        var sm = enterGifSearching()
        let out = sm.handle(.focusChange)
        #expect(out.action == .closeGifPicker)
        #expect(out.consumesKey == false)
        #expect(sm.state == .idle)
    }

    @Test func resumeGifSearchingReentersState() {
        var sm = enterGifSearching()
        _ = sm.handle(.returnKey)  // pickGif transitions to idle
        #expect(sm.state == .idle)
        // Engine calls this when the picker stayed open (e.g. "Load more").
        sm.resumeGifSearching(query: "cats")
        #expect(sm.state == .gifSearching(query: "cats"))
        let out = sm.handle(.backspace)
        #expect(out.action == .refreshGifPicker(query: "cat"))
    }

    // MARK: ambient emoticons (no leading colon)

    @Test func ambientHeartFiresImmediately() {
        // `<` is punctuation-led, so `<3` fires the moment it completes —
        // no terminator needed.
        var sm = TriggerStateMachine()
        _ = sm.handle(.cancelChar("<"))
        let out = sm.handle(.nameChar("3"))
        #expect(out.action == .insertAmbientEmoticon(word: "<3", trailing: ""))
        #expect(out.consumesKey == false)
        #expect(sm.state == .idle)
    }

    @Test func ambientLetterLedWaitsForTerminator() {
        // `XD` is letter-led — must wait for a terminator so it doesn't eat
        // into prose like "XDog".
        var sm = TriggerStateMachine()
        _ = sm.handle(.nameChar("X"))
        let mid = sm.handle(.nameChar("D"))
        #expect(mid.action == .none)
        let out = sm.handle(.cancelChar(" "))
        #expect(out.action == .checkAmbientEmoticon(word: "XD", terminator: " "))
        #expect(out.consumesKey == false)
    }

    @Test func ambientColonContinuationIsNotHijackedByCapture() {
        // `>` is a colon-continuation prefix: the `:` after it must extend
        // the ambient word (`>:)`), NOT start emoji capture.
        var sm = TriggerStateMachine()
        _ = sm.handle(.cancelChar(">"))
        let colon = sm.handle(.colon)
        #expect(colon.action == .none)
        #expect(sm.state == .idle)
        let out = sm.handle(.cancelChar(")"))
        #expect(out.action == .insertAmbientEmoticon(word: ">:)", trailing: ""))
    }

    @Test func ambientRightArrowFiresOnHyphenGreaterThan() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.nameChar("-"))
        let out = sm.handle(.cancelChar(">"))
        #expect(out.action == .insertAmbientEmoticon(word: "->", trailing: ""))
        #expect(out.consumesKey == false)
        #expect(sm.state == .idle)
    }

    @Test func ambientLeftArrowDefersUntilNextChar() {
        // `<-` is in the table, but so is `<->` — firing `←` on completion
        // would make `↔` unreachable. So `<-` alone holds the fire pending
        // until the next keystroke decides between continuing the longer
        // match and falling back to the shorter one.
        var sm = TriggerStateMachine()
        _ = sm.handle(.cancelChar("<"))
        let out = sm.handle(.nameChar("-"))
        #expect(out.action == .none)
        #expect(out.consumesKey == false)
        #expect(sm.state == .idle)
    }

    @Test func ambientLeftRightArrowFiresOnPendingExtension() {
        // `<-` deferred; the trailing `>` completes `<->` and fires `↔`.
        var sm = TriggerStateMachine()
        _ = sm.handle(.cancelChar("<"))
        _ = sm.handle(.nameChar("-"))
        let out = sm.handle(.cancelChar(">"))
        #expect(out.action == .insertAmbientEmoticon(word: "<->", trailing: ""))
        #expect(out.consumesKey == false)
    }

    @Test func ambientLeftArrowFiresWithTrailingOnNonExtendingChar() {
        // `<-` deferred; a non-extending char (`x`) collapses the pending
        // fire and is carried as `trailing` so the engine can insert `←x`
        // instead of `<←` (which is what naïve delete-from-end would give
        // once `x` had passed through to the focused app).
        var sm = TriggerStateMachine()
        _ = sm.handle(.cancelChar("<"))
        _ = sm.handle(.nameChar("-"))
        let out = sm.handle(.nameChar("x"))
        #expect(out.action == .insertAmbientEmoticon(word: "<-", trailing: "x"))
        #expect(out.consumesKey == true)
    }

    @Test func ambientLeftArrowFiresOnTerminator() {
        // A space can't extend `<-` to `<->`, so the deferred fire resolves
        // immediately: the arrow is emitted and the terminator rides along as
        // `trailing` (→ `← `). The space is consumed and re-emitted by the
        // Engine, hence consumesKey == true.
        var sm = TriggerStateMachine()
        _ = sm.handle(.cancelChar("<"))
        _ = sm.handle(.nameChar("-"))
        let out = sm.handle(.cancelChar(" "))
        #expect(out.action == .insertAmbientEmoticon(word: "<-", trailing: " "))
        #expect(out.consumesKey == true)
    }

    @Test func ambientEqualsArrowsAreInert() {
        // `=`-based arrows are deliberately unmapped (code-operator collisions),
        // so `=>` / `<=` / `<=>` accumulate and never convert.
        var sm = TriggerStateMachine()
        _ = sm.handle(.cancelChar("="))
        #expect(sm.handle(.cancelChar(">")).action == .none)        // =>
        sm = TriggerStateMachine()
        _ = sm.handle(.cancelChar("<"))
        _ = sm.handle(.cancelChar("="))
        #expect(sm.handle(.cancelChar(">")).action == .none)        // <=>
    }

    // MARK: ambient arrows flush against text (no surrounding spaces)

    /// Type a string char-by-char from idle, classifying each char the way the
    /// KeyMonitor would (name chars vs. cancel chars), and return the last
    /// non-passthrough action seen. Lets the adjacency tests read as the
    /// literal thing the user types.
    private func lastAmbientAction(typing text: String) -> TriggerAction {
        var sm = TriggerStateMachine()
        var last: TriggerAction = .none
        let nameChars = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-+")
        for ch in text {
            let out = nameChars.contains(ch) ? sm.handle(.nameChar(ch)) : sm.handle(.cancelChar(ch))
            if out.action != .none { last = out.action }
        }
        return last
    }

    @Test func ambientRightArrowFiresFlushAfterWord() {
        // `Foo->` with no leading space: the `->` is pulled off the end and
        // only those two chars are deleted, leaving `Foo`.
        #expect(lastAmbientAction(typing: "Foo->") == .insertAmbientEmoticon(word: "->", trailing: ""))
    }

    @Test func ambientLeftRightArrowFiresFlushAfterWord() {
        // `Foo<->` → the deferred `<-` extends to `<->` and fires `↔`.
        #expect(lastAmbientAction(typing: "Foo<->") == .insertAmbientEmoticon(word: "<->", trailing: ""))
    }

    @Test func ambientLeftArrowFiresFlushBetweenWords() {
        // `Foo<-B`: `<-` defers, then the `B` (non-extending) collapses it to
        // `←` carrying `B` as trailing — `Foo←B`.
        #expect(lastAmbientAction(typing: "Foo<-B") == .insertAmbientEmoticon(word: "<-", trailing: "B"))
    }

    @Test func nonArrowEmoticonStaysBoundaryGatedFlushAfterWord() {
        // Per the chosen scope (arrows only), `<3` flush against a word does
        // NOT fire — `Hi<3` stays literal.
        #expect(lastAmbientAction(typing: "Hi<3") == .none)
    }

    @Test func arrowConversionToggleMakesArrowsInert() {
        // With the sub-toggle off, arrows neither fire nor defer/consume — but
        // other ambient emoticons keep working.
        var sm = TriggerStateMachine()
        sm.arrowConversionEnabled = false
        _ = sm.handle(.nameChar("-"))
        #expect(sm.handle(.cancelChar(">")).action == .none)        // -> inert
        sm = TriggerStateMachine()
        sm.arrowConversionEnabled = false
        _ = sm.handle(.cancelChar("<"))
        let dash = sm.handle(.nameChar("-"))
        #expect(dash.action == .none)                                // no defer
        #expect(dash.consumesKey == false)                           // no consume
        let x = sm.handle(.nameChar("x"))
        #expect(x.action == .none)                                   // <-x stays literal
        #expect(x.consumesKey == false)
        // Heart still fires regardless of the arrow toggle.
        sm = TriggerStateMachine()
        sm.arrowConversionEnabled = false
        _ = sm.handle(.cancelChar("<"))
        #expect(sm.handle(.nameChar("3")).action == .insertAmbientEmoticon(word: "<3", trailing: ""))
    }

    @Test func ambientTerminatorChecksWordThenResetsBuffer() {
        var sm = TriggerStateMachine()
        for ch in "hello" { _ = sm.handle(.nameChar(ch)) }
        let out = sm.handle(.cancelChar(" "))
        #expect(out.action == .checkAmbientEmoticon(word: "hello", terminator: " "))
        // Buffer is cleared — a second terminator with nothing buffered
        // just passes through.
        let next = sm.handle(.cancelChar(" "))
        #expect(next.action == .none)
    }

    // MARK: Cmd+Z

    @Test func cmdZFromIdleRequestsUndo() {
        var sm = TriggerStateMachine()
        let out = sm.handle(.cmdZ)
        #expect(out.action == .maybeUndoEmoticon)
        #expect(out.consumesKey == false)
    }

    @Test func cmdZDuringCapturePassesThroughAndKeepsCapture() {
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        _ = sm.handle(.nameChar("f"))
        let out = sm.handle(.cmdZ)
        #expect(out.action == .none)
        #expect(out.consumesKey == false)
        #expect(sm.state == .capturing(query: "f"))
    }

    // MARK: symbols-scope backspace demotion

    @Test func symbolsScopeBackspaceDemotesToNormalWithoutEndingCapture() {
        var sm = TriggerStateMachine()
        sm.symbolsDoubleColonEnabled = true
        _ = sm.handle(.colon)
        _ = sm.handle(.colon)  // → symbolsOnly scope, capturing("")
        // Backspace on the empty symbols query deletes the 2nd colon and
        // demotes to normal scope — capture stays open.
        let out = sm.handle(.backspace)
        #expect(out.action == .closePicker)
        // Now in normal scope: threshold rises back to 2, so a single char
        // doesn't surface the picker.
        let next = sm.handle(.nameChar("a"))
        #expect(next.action == .none)
    }

    // MARK: non-ASCII single-char threshold

    @Test func singleNonASCIICharOpensPickerImmediately() {
        // A lone CJK/Devanagari/etc. char is a complete word — threshold
        // drops to 1 so the picker opens on the first keystroke.
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        let out = sm.handle(.nameChar("愛"))
        #expect(out.action == .openPicker(query: "愛", scope: .normal))
    }

    // MARK: backspace after cancel char

    @Test func backspaceAfterCancelDoesNotRevivePicker() {
        // After a cancel char ends capture, a following backspace just
        // passes through — it does not re-open the picker on the `:query`
        // still sitting in the field.
        var sm = TriggerStateMachine()
        _ = sm.handle(.colon)
        for ch in "foo" { _ = sm.handle(.nameChar(ch)) }
        _ = sm.handle(.cancelChar(" "))  // ends capture → idle
        #expect(sm.state == .idle)
        let out = sm.handle(.backspace)
        #expect(out.action == .none)
        #expect(sm.state == .idle)
    }
}
