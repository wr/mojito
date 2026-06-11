import Foundation

enum TriggerState: Equatable {
    case idle
    case capturing(query: String)
    /// Active while the GIF picker is up. Consumes keystrokes and forwards
    /// them to the picker's view model via `.refreshGifPicker`, so typing
    /// after `:::` lands in the GIF search box (not the focused app).
    case gifSearching(query: String)
    /// Active while the full-library browser grid is up (the picker panel,
    /// grown). Consumes keystrokes and routes them to the browser — search,
    /// grid navigation, pick — so nothing leaks into the focused app.
    case browsing(query: String)
}

/// `:foo` = full corpus, `::foo` = experimental Symbols set
/// (only reachable when `symbolsRequireDoubleColon` is on).
enum CaptureScope: Equatable {
    case normal
    case symbolsOnly
}

enum TriggerInput {
    /// a–z, 0–9, _, -, +
    case nameChar(Character)
    case backspace
    case colon
    case escape
    case returnKey
    case tabKey
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    /// Anything else that ends capture. Carries the char for the emoticon table.
    case cancelChar(Character)
    case focusChange
    /// Cmd+Z with no other modifiers. Routed through so Engine can undo a
    /// recent emoticon; passes through when nothing's pending.
    case cmdZ
}

/// **Design choice:** during capture, the `:` and name chars pass through to
/// the focused app and appear as typed. We only delete `:query` when an emoji
/// actually resolves. This means typing `:` literally (e.g. "9:00 PM") just
/// works — if a non-name char follows, capture cancels and the `:` stays.
struct TriggerOutput: Equatable {
    let action: TriggerAction
    let consumesKey: Bool

    static let passthrough = TriggerOutput(action: .none, consumesKey: false)
    static let consume = TriggerOutput(action: .none, consumesKey: true)
}

enum InsertMode: Equatable {
    /// Return / Tab — use whatever the picker has selected (incl. easter
    /// eggs and the random row).
    case fromPicker
    /// Closing `:` — insert only on an exact shortcode/sentinel match.
    /// Near-misses leave `:query:` untouched.
    case exactMatch
}

enum TriggerAction: Equatable {
    case none
    case openPicker(query: String, scope: CaptureScope)
    case refreshPicker(query: String, scope: CaptureScope)
    case closePicker
    case moveSelection(delta: Int)
    /// Delete `:query` (or `:query:` for exactMatch) and insert the
    /// resolved emoji, if any.
    case insertEmoji(query: String, mode: InsertMode, scope: CaptureScope)
    /// Terminator received during capture. Engine looks up
    /// `:query<terminator>` in the emoticon table; terminator was passed
    /// through. Never fires in symbols-only scope.
    case checkEmoticon(query: String, terminator: Character)
    /// User paused too long for this to be an emoticon attempt — close the
    /// picker and leave `:query<term>` in place.
    case abortEmoticon
    /// Undo the most recent emoticon insertion if one is within the window.
    case maybeUndoEmoticon
    /// Konami code completed. `deleteCount` is currently always 0 (all
    /// sequence keys are consumed) but kept for defense.
    case triggerKonami(deleteCount: Int)
    /// Word + terminator, no leading colon. Engine looks up the word in
    /// `AmbientEmoticonTable` and replaces with `emoji + terminator`.
    case checkAmbientEmoticon(word: String, terminator: Character)
    /// Ambient match that doesn't need a terminator (e.g. `<3`, `>:)`).
    /// Engine deletes `word.count` and replaces with `emoji + trailing`.
    /// `trailing` is non-empty when a deferred shorter match (`<-`) fires
    /// because the following char (`x` in `<-x`) didn't extend it to a
    /// longer one (`<->`); the state machine consumes that char so it
    /// can be re-emitted after the emoji.
    case insertAmbientEmoticon(word: String, trailing: String)
    /// User typed `:::` (three colons within `gifTripleColonWindow`).
    /// The colons stay in the focused app — they're deleted alongside
    /// the query only when the user picks a GIF. Backspacing through
    /// the colons gradually peels the picker shut, matching emoji UX.
    case openGifPicker
    /// Updated GIF search query — Engine writes to the picker's view model.
    case refreshGifPicker(query: String)
    /// Close the GIF picker (esc, click-away, focus change).
    case closeGifPicker
    /// Enter pressed inside the GIF picker — delete `deleteCount` chars
    /// (the post-`:::` query that was typed through to the focused app),
    /// then copy the selected GIF and synthesize a ⌘V paste.
    case pickGif(deleteCount: Int)
    /// Arrow-key navigation across the GIF grid.
    case moveGifSelection(direction: GifMoveDirection)
    /// Browser search query changed — Engine writes it to the browser model.
    case refreshBrowser(query: String)
    /// Arrow-key navigation across the browser grid.
    case moveBrowser(direction: GifMoveDirection)
    /// Enter / click in the browser — insert the selected emoji.
    case pickBrowser
    /// Close the browser grid (esc, backspace past empty, click-away).
    case closeBrowser
    /// Grow the favorites pill into the full browser grid (↓/↑ on the pill).
    case expandBrowser
    /// Pill quick-pick: insert the row at this index (digit 1–8 → 0–7).
    case pickIndex(Int)
    /// Close the pill and restore the swallowed `?` so `:?`+Esc leaves `:?`.
    case closePickerRestoringQuestion
}

enum GifMoveDirection: Equatable { case left, right, up, down }

struct TriggerStateMachine {
    var state: TriggerState = .idle

    /// When true, `::` upgrades the capture to symbols-only instead of cancelling.
    var symbolsDoubleColonEnabled: Bool = false

    /// Gates the arrow family (`->`, `<-`, `<->`). When false, arrows are
    /// inert — never matched as a suffix, never deferred, never consume a
    /// following char — so they read as plain text. The Engine sets it from
    /// `PrefsKey.arrowConversionEnabled`. Other ambient emoticons (`<3`, …)
    /// are unaffected. Turning it off drops any deferred arrow match, so a
    /// fire held back before the toggle flipped can't land after it.
    var arrowConversionEnabled: Bool = true {
        didSet {
            if !arrowConversionEnabled { pendingImmediateFire = nil }
        }
    }

    /// The character that, typed right after a bare `:`, opens the Quick Access
    /// pill (e.g. `?` → `:?`). `nil` disables it. The Engine sets it from
    /// `PrefsKey.quickAccessTriggerChar`. Must be a `.cancelChar`-class glyph
    /// (punctuation/symbol) since it's matched in the cancelChar branch.
    var quickAccessTrigger: Character?

    /// True only once the empty-query favorites picker is actually on screen.
    /// The Engine sets it after the (debounced) show and clears it on hide,
    /// so navigation keys are claimed for the picker *only* while it's
    /// visible — a bare `:` followed by a fast keystroke never hijacks the
    /// arrow keys or Return. Cleared internally whenever capture leaves the
    /// empty-query state.
    var emptyPickerActive: Bool = false

    /// Selectable emoji rows in the pill (excludes the trailing Browse row).
    /// The Engine sets it alongside `emptyPickerActive`; it bounds the digit
    /// quick-pick so an out-of-range digit falls through to a normal search
    /// instead of being swallowed.
    var pillEmojiCount: Int = 0

    private var currentScope: CaptureScope = .normal
    /// The active capture's scope. Read by the Engine's global-hotkey browser
    /// entry, which synthesizes a pick outside the normal action flow and needs
    /// to know whether the field holds `:query` or `::query`.
    var captureScope: CaptureScope { currentScope }

    private var konamiProgress: Int = 0
    private enum KonamiStep { case up, down, left, right, b, a }
    private static let konamiSequence: [KonamiStep] = [
        .up, .up, .down, .down, .left, .right, .left, .right, .b, .a
    ]
    private static func konamiMatches(_ input: TriggerInput, _ step: KonamiStep) -> Bool {
        switch (input, step) {
        case (.arrowUp, .up), (.arrowDown, .down),
             (.arrowLeft, .left), (.arrowRight, .right):
            return true
        case (.nameChar(let c), .b):
            return c == "b" || c == "B"
        case (.nameChar(let c), .a):
            return c == "a" || c == "A"
        default:
            return false
        }
    }

    /// True after a letter/digit/etc. — gates `:` so "5:35" / "foo:bar"
    /// don't fire the picker. Conservatively false after backspace, arrows,
    /// focus changes so the picker still opens after non-typing caret motion.
    private var lastWasWordChar: Bool = false

    /// Used by `cancelChar` to compare against `emoticonMaxIdle`.
    private var lastCaptureKeystrokeAt: Date? = nil

    private static let emoticonMaxIdle: TimeInterval = 1.0

    /// Chars typed in `.idle` since the last terminator. Drives ambient
    /// emoticon detection (`<3 `, `XD `, `>:) `).
    private var idleWord: String = ""

    private var lastIdleKeystrokeAt: Date? = nil

    /// A complete ambient match whose fire we've held back because some
    /// strictly-longer key in the table also starts with it (e.g. `<-` is
    /// in the map, but so is `<->` — fire too early and the user can never
    /// reach `↔`). Resolves on the very next idle keystroke: if it extends
    /// toward the longer match, normal accumulation takes over; otherwise
    /// the pending word fires now with that extra char carried as `trailing`.
    private var pendingImmediateFire: (word: String, emoji: String)?

    /// Sliding window of recent colon timestamps used to detect `:::`
    /// (the GIF-search trigger) regardless of the current capture state.
    private var recentColonTimes: [Date] = []
    /// Generous window so "comfortably-fast" three-colon typing still
    /// counts. Tight enough that a stray `:` from earlier in the sentence
    /// doesn't combine with a normal `::` later.
    private static let gifTripleColonWindow: TimeInterval = 1.5

    /// Closing brackets like `)` are deliberately absent — they're part of
    /// emoticons (`B)`, `>:)`).
    private static let ambientTerminators: Set<Character> = [
        " ", "\t", "\n", ".", ",", ";", "!", "?",
    ]

    mutating func handle(_ input: TriggerInput) -> TriggerOutput {
        // One timestamp per keystroke — every window check and stamp in
        // this pass measures against the same instant.
        let now = Date()

        // Drop a stale ambient word after too long a pause (covers
        // click-to-move-caret followed by delayed typing). A deferred
        // fire is dropped without firing — the user moved on, and we'd
        // have no way to emit the held action without also dropping
        // whatever input arrived next.
        if let last = lastIdleKeystrokeAt,
           now.timeIntervalSince(last) > Self.emoticonMaxIdle {
            idleWord = ""
            lastIdleKeystrokeAt = nil
            pendingImmediateFire = nil
        }

        let output = process(input, now: now)
        if case .idle = state {
            switch input {
            case .nameChar: lastWasWordChar = true
            default:        lastWasWordChar = false
            }
            lastCaptureKeystrokeAt = nil
        } else {
            // Stamp every contributing keystroke so the >1s window is
            // measured against the most recent one, not the opening colon.
            switch input {
            case .colon, .nameChar, .backspace:
                lastCaptureKeystrokeAt = now
            default:
                break
            }
        }
        return output
    }

    private mutating func process(_ input: TriggerInput, now: Date) -> TriggerOutput {
        // While the GIF picker is showing, the state machine owns the
        // keyboard — namechars + arrows + enter + esc + backspace are
        // forwarded to the picker view model and consumed so they don't
        // double-feed into the focused app underneath.
        if case .gifSearching = state {
            return handleGifSearching(input)
        }

        // While the browser grid is up, it owns the keyboard — everything is
        // consumed and routed to the browser model so nothing leaks into the
        // focused app underneath.
        if case .browsing = state {
            return handleBrowsing(input)
        }

        // `:::` within `gifTripleColonWindow` opens the GIF picker no
        // matter what the capture state is. Runs before everything else
        // so it overrides the normal colon flow.
        if case .colon = input {
            recentColonTimes.append(now)
            recentColonTimes = recentColonTimes.filter {
                now.timeIntervalSince($0) <= Self.gifTripleColonWindow
            }
            if recentColonTimes.count >= 3 {
                recentColonTimes.removeAll()
                state = .gifSearching(query: "")
                currentScope = .normal
                konamiProgress = 0
                idleWord = ""
                lastIdleKeystrokeAt = nil
                pendingImmediateFire = nil
                return TriggerOutput(action: .openGifPicker, consumesKey: false)
            }
        } else {
            recentColonTimes.removeAll()
        }

        // Konami only runs in `.capturing(query: "")` (right after `:`).
        // Tracking it from idle would eat arrow keys globally and break
        // caret navigation. Fires on the final `A` — no closing `:`.
        // Skipped while the empty-query favorites picker is visible, which
        // owns the arrow keys; that picker only appears after a deliberate
        // dwell, so fast arrow input still flows here.
        if case .capturing(let q) = state, q.isEmpty, !emptyPickerActive {
            if konamiProgress < Self.konamiSequence.count,
               Self.konamiMatches(input, Self.konamiSequence[konamiProgress]) {
                konamiProgress += 1
                NSLog("[mojito] konami: step \(konamiProgress)/\(Self.konamiSequence.count) matched")
                if konamiProgress == Self.konamiSequence.count {
                    NSLog("[mojito] konami: sequence complete; firing payoff")
                    state = .idle
                    konamiProgress = 0
                    currentScope = .normal
                    return TriggerOutput(action: .triggerKonami(deleteCount: 1), consumesKey: true)
                }
                return .consume
            }
            konamiProgress = 0
        } else {
            konamiProgress = 0
        }

        switch (state, input) {

        // Unreachable — handled by the early returns above; kept for exhaustiveness.
        case (.gifSearching, _), (.browsing, _):
            return .passthrough

        // MARK: Cmd+Z — must come before the `(.idle, _)` catch-all below.

        case (.idle, .cmdZ):
            // Engine decides whether to actually undo. Drop the ambient
            // buffer — Cmd+Z is a context switch.
            idleWord = ""
            lastIdleKeystrokeAt = nil
            return TriggerOutput(action: .maybeUndoEmoticon, consumesKey: false)

        case (.capturing, .cmdZ):
            // Mid-capture: there's no pending undo entry anyway. Pass through.
            return .passthrough

        // MARK: idle

        case (.idle, .colon):
            // Carve-out so `>:)` etc. survive: if the colon-continuation
            // prefix is in the buffer (currently just `>`), append the
            // colon to the ambient word instead of starting capture —
            // otherwise the colon path would convert `:)` and leave `>`
            // behind.
            if AmbientEmoticonTable.colonContinuationPrefixes.contains(idleWord) {
                idleWord += ":"
                lastIdleKeystrokeAt = now
                if let fire = checkImmediateAmbientFire() {
                    return fire
                }
                return TriggerOutput(action: .none, consumesKey: false)
            }
            idleWord = ""
            lastIdleKeystrokeAt = nil
            pendingImmediateFire = nil
            if lastWasWordChar {
                // "5:35" / "foo:bar" — don't trigger.
                return .passthrough
            }
            currentScope = .normal
            state = .capturing(query: "")
            // Not visible yet — the Engine flips this on after the debounced
            // show. Clearing here keeps a prior capture's value from leaking
            // into a fresh `:`.
            emptyPickerActive = false
            // A bare `:` just starts capturing; the Quick Access pill is
            // summoned by the trigger char that follows (`:?`), handled in the
            // cancelChar branch below.
            return TriggerOutput(action: .none, consumesKey: false)

        case (.idle, .backspace):
            if !idleWord.isEmpty {
                idleWord = String(idleWord.dropLast())
                lastIdleKeystrokeAt = idleWord.isEmpty ? nil : now
            }
            pendingImmediateFire = nil
            return .passthrough

        case (.idle, .nameChar(let c)):
            if let fire = resolvePendingFire(with: c) {
                return fire
            }
            idleWord += String(c)
            lastIdleKeystrokeAt = now
            if let fire = checkImmediateAmbientFire() {
                return fire
            }
            return .passthrough

        case (.idle, .cancelChar(let c)):
            // A pending arrow (`<-`/`<=`) resolves against whatever comes next.
            // A terminator can't extend it to `<->`/`<=>`, so it fires here and
            // carries the terminator through as `trailing` — this is what makes
            // `Foo<- ` convert (the whole-word lookup below would miss `Foo<-`).
            if let fire = resolvePendingFire(with: c) {
                return fire
            }
            if Self.ambientTerminators.contains(c) {
                // Terminator — look up the buffered word, then reset.
                let word = idleWord
                idleWord = ""
                lastIdleKeystrokeAt = nil
                pendingImmediateFire = nil
                if word.isEmpty {
                    return .passthrough
                }
                return TriggerOutput(
                    action: .checkAmbientEmoticon(word: word, terminator: c),
                    consumesKey: false
                )
            }
            // Non-terminator punctuation (`<`, `>`, `)`, `(`, `_`, …) is
            // part of an emoticon body. Append and keep accumulating.
            idleWord += String(c)
            lastIdleKeystrokeAt = now
            if let fire = checkImmediateAmbientFire() {
                return fire
            }
            return .passthrough

        case (.idle, _):
            // Arrows / focus change / escape / return/tab in idle — caret
            // motion or context switch. Drop the buffer.
            idleWord = ""
            lastIdleKeystrokeAt = nil
            pendingImmediateFire = nil
            return .passthrough

        // MARK: capturing — colon

        case (.capturing(let q), .colon) where q.isEmpty:
            if symbolsDoubleColonEnabled, currentScope == .normal {
                // `::` upgrades to symbols-only; second colon passes through.
                currentScope = .symbolsOnly
                return TriggerOutput(action: .none, consumesKey: false)
            }
            // `::` cancels. Both colons stay in text.
            state = .idle
            currentScope = .normal
            return TriggerOutput(action: .closePicker, consumesKey: false)

        case (.capturing(let q), .colon):
            // Closing `:` passes through so text reads `:query:`. Engine
            // deletes the span only on exact match; near-misses stay put.
            let scope = currentScope
            state = .idle
            currentScope = .normal
            return TriggerOutput(action: .insertEmoji(query: q, mode: .exactMatch, scope: scope), consumesKey: false)

        // MARK: capturing — name characters

        case (.capturing(let q), .nameChar(let c)):
            // Pill quick-pick: while the pill is up, a digit 1–8 inserts that
            // row directly (`:?3` → 3rd emoji). Swallowed so it doesn't start
            // a search.
            if emptyPickerActive, let digit = c.wholeNumberValue,
               digit >= 1, digit <= min(8, pillEmojiCount) {
                return TriggerOutput(action: .pickIndex(digit - 1), consumesKey: true)
            }
            // First typed char leaves the empty-query state — drop the
            // favorites picker if it was up.
            let wasEmptyPicker = emptyPickerActive
            emptyPickerActive = false
            let next = q + String(c)
            state = .capturing(query: next)
            let threshold = pickerThreshold(for: currentScope, query: next)
            let action: TriggerAction
            if next.count < threshold {
                // Keep capturing silently so a terminator can still fire
                // `:D `, but don't surface the picker on a single char.
                // If favorites were showing, close them as typing begins.
                action = wasEmptyPicker ? .closePicker : .none
            } else if q.count < threshold {
                action = .openPicker(query: next, scope: currentScope)
            } else {
                action = .refreshPicker(query: next, scope: currentScope)
            }
            return TriggerOutput(action: action, consumesKey: false)

        // MARK: capturing — backspace

        case (.capturing(let q), .backspace):
            if q.isEmpty {
                // Symbols scope demotes to normal so the backspace deletes
                // the second colon; normal scope goes fully idle.
                if currentScope == .symbolsOnly {
                    currentScope = .normal
                    return TriggerOutput(action: .closePicker, consumesKey: false)
                }
                state = .idle
                return TriggerOutput(action: .closePicker, consumesKey: false)
            }
            let next = String(q.dropLast())
            state = .capturing(query: next)
            let threshold = pickerThreshold(for: currentScope, query: next)
            let action: TriggerAction = next.count < threshold
                ? .closePicker
                : .refreshPicker(query: next, scope: currentScope)
            return TriggerOutput(action: action, consumesKey: false)

        // MARK: capturing — picker navigation

        case (.capturing(let q), .arrowUp):
            if q.isEmpty {
                // Pill: both ↑ and ↓ expand into the full grid. Without the
                // pill, ↑ on a bare `:` passes through (caret motion).
                return emptyPickerActive
                    ? TriggerOutput(action: .expandBrowser, consumesKey: true)
                    : .passthrough
            }
            return TriggerOutput(action: .moveSelection(delta: -1), consumesKey: true)

        case (.capturing(let q), .arrowDown):
            if q.isEmpty {
                // Pill: ↓ grows it into the full browser grid.
                return emptyPickerActive
                    ? TriggerOutput(action: .expandBrowser, consumesKey: true)
                    : .passthrough
            }
            return TriggerOutput(action: .moveSelection(delta: 1), consumesKey: true)

        case (.capturing(let q), .arrowLeft):
            // The compact favorites pill is horizontal — ←/→ drive its
            // selection while it's visible.
            if emptyPickerActive {
                return TriggerOutput(action: .moveSelection(delta: -1), consumesKey: true)
            }
            // Otherwise eat ← / → so the caret can't drift out of `:query`,
            // or end capture if we're sitting on a bare `:`.
            if q.isEmpty {
                state = .idle
                return TriggerOutput(action: .closePicker, consumesKey: false)
            }
            return .consume

        case (.capturing(let q), .arrowRight):
            if emptyPickerActive {
                return TriggerOutput(action: .moveSelection(delta: 1), consumesKey: true)
            }
            if q.isEmpty {
                state = .idle
                return TriggerOutput(action: .closePicker, consumesKey: false)
            }
            return .consume

        case (.capturing(let q), .returnKey), (.capturing(let q), .tabKey):
            if q.isEmpty {
                // Favorites picker visible: Return/Tab picks the highlighted
                // favorite (or the Browse row). Otherwise `:`+Return is just
                // a literal colon — pass it through untouched.
                if emptyPickerActive {
                    emptyPickerActive = false
                    state = .idle
                    currentScope = .normal
                    return TriggerOutput(action: .insertEmoji(query: "", mode: .fromPicker, scope: .normal), consumesKey: true)
                }
                state = .idle
                currentScope = .normal
                return TriggerOutput(action: .closePicker, consumesKey: false)
            }
            let scope = currentScope
            state = .idle
            currentScope = .normal
            return TriggerOutput(action: .insertEmoji(query: q, mode: .fromPicker, scope: scope), consumesKey: true)

        // MARK: capturing — exits

        case (.capturing, .escape):
            // `:?`+Esc should leave the literal `:?` — the `?` was swallowed
            // when the pill opened, so ask the Engine to type it back.
            let restoreQuestion = emptyPickerActive && quickAccessTrigger != nil
            emptyPickerActive = false
            state = .idle
            currentScope = .normal
            return TriggerOutput(
                action: restoreQuestion ? .closePickerRestoringQuestion : .closePicker,
                consumesKey: true
            )

        case (.capturing(let q), .cancelChar(let c)) where q.isEmpty && quickAccessTrigger == c:
            // `:<trigger>` (e.g. `:?`) summons the Quick Access pill. Swallow
            // the trigger char so the focused app only ever holds the `:` —
            // deleted on pick, so the insert delete-count stays 1.
            return TriggerOutput(action: .openPicker(query: "", scope: .normal), consumesKey: true)

        case (.capturing(let q), .cancelChar(let c)):
            // Symbols-only skips emoticons entirely (it's an emoji feature).
            let wasSymbolsOnly = currentScope == .symbolsOnly
            let lastAt = lastCaptureKeystrokeAt
            state = .idle
            currentScope = .normal
            if wasSymbolsOnly {
                return TriggerOutput(action: .closePicker, consumesKey: false)
            }
            // Long pause before terminator → user was mid-sentence; this
            // isn't an emoticon attempt.
            if let lastAt, now.timeIntervalSince(lastAt) > Self.emoticonMaxIdle {
                return TriggerOutput(action: .abortEmoticon, consumesKey: false)
            }
            return TriggerOutput(action: .checkEmoticon(query: q, terminator: c), consumesKey: false)

        case (.capturing, .focusChange):
            state = .idle
            currentScope = .normal
            return TriggerOutput(action: .closePicker, consumesKey: false)
        }
    }

    /// Engine calls this when an Enter on the GIF picker was consumed by
    /// the "Load more" affordance — the picker stays open, so the state
    /// machine needs to stay in `.gifSearching` rather than the `.idle`
    /// state the Enter handler just transitioned it to.
    mutating func resumeGifSearching(query: String) {
        state = .gifSearching(query: query)
    }

    /// Engine calls this when the pill's Browse row (or the menu) opens the
    /// full grid: hand the keyboard to the browser.
    mutating func enterBrowsing(query: String) {
        state = .browsing(query: query)
        emptyPickerActive = false
        konamiProgress = 0
    }

    /// Keep the state machine's browser query in sync when a mouse action
    /// (category tab) resets the search.
    mutating func setBrowsingQuery(_ query: String) {
        if case .browsing = state {
            state = .browsing(query: query)
        }
    }

    mutating func reset() {
        state = .idle
        currentScope = .normal
        emptyPickerActive = false
        pillEmojiCount = 0
        lastWasWordChar = false
        konamiProgress = 0
        idleWord = ""
        lastIdleKeystrokeAt = nil
        lastCaptureKeystrokeAt = nil
        recentColonTimes.removeAll()
        pendingImmediateFire = nil
    }

    /// 2 chars in the normal corpus so `:D` / `:s` don't briefly flash the
    /// picker. Symbols scope stays at 1 because its corpus is mostly single-
    /// char entries. A single non-ASCII char (`愛` / `心` / `सूर्य` / `कक्षा`)
    /// is a complete CJK / Devanagari / Cyrillic / Arabic word — drop to 1
    /// there too, since those aren't candidates for English-emoticon false
    /// positives.
    private func pickerThreshold(for scope: CaptureScope, query: String) -> Int {
        if scope == .symbolsOnly { return 1 }
        if query.unicodeScalars.contains(where: { $0.value > 0x7F }) { return 1 }
        return 2
    }

    /// Mirrors the user's typing into the GIF picker's view model while
    /// letting the characters fall through to the focused app. Mirrors how
    /// the emoji picker works (`:foo` is visible in the app's text field
    /// while the picker is showing). Arrows / Enter / Esc are consumed.
    private mutating func handleGifSearching(_ input: TriggerInput) -> TriggerOutput {
        guard case .gifSearching(let q) = state else { return .passthrough }
        switch input {
        case .nameChar(let c):
            let next = q + String(c)
            state = .gifSearching(query: next)
            return TriggerOutput(action: .refreshGifPicker(query: next), consumesKey: false)
        case .colon:
            // Treat as part of the query — quirky searches still go through.
            let next = q + ":"
            state = .gifSearching(query: next)
            return TriggerOutput(action: .refreshGifPicker(query: next), consumesKey: false)
        case .cancelChar(let c):
            // Space + punctuation are valid in GIF queries
            // ("spongebob imagination", "you're welcome").
            let next = q + String(c)
            state = .gifSearching(query: next)
            return TriggerOutput(action: .refreshGifPicker(query: next), consumesKey: false)
        case .backspace:
            if q.isEmpty {
                state = .idle
                return TriggerOutput(action: .closeGifPicker, consumesKey: false)
            }
            let next = String(q.dropLast())
            state = .gifSearching(query: next)
            return TriggerOutput(action: .refreshGifPicker(query: next), consumesKey: false)
        case .escape:
            state = .idle
            return TriggerOutput(action: .closeGifPicker, consumesKey: true)
        case .returnKey, .tabKey:
            state = .idle
            // `:::` + query are all sitting in the focused app — delete the
            // full span so the GIF replaces the typed trigger.
            return TriggerOutput(action: .pickGif(deleteCount: q.count + 3), consumesKey: true)
        case .arrowUp:
            return TriggerOutput(action: .moveGifSelection(direction: .up), consumesKey: true)
        case .arrowDown:
            return TriggerOutput(action: .moveGifSelection(direction: .down), consumesKey: true)
        case .arrowLeft:
            return TriggerOutput(action: .moveGifSelection(direction: .left), consumesKey: true)
        case .arrowRight:
            return TriggerOutput(action: .moveGifSelection(direction: .right), consumesKey: true)
        case .focusChange:
            state = .idle
            return TriggerOutput(action: .closeGifPicker, consumesKey: false)
        case .cmdZ:
            state = .idle
            return TriggerOutput(action: .closeGifPicker, consumesKey: false)
        }
    }

    /// Routes keystrokes to the full-library browser grid. Everything is
    /// consumed — the browser owns the keyboard while it's up, so typing,
    /// arrows, and Enter never reach the focused app (only the final pick is
    /// synthesized there).
    private mutating func handleBrowsing(_ input: TriggerInput) -> TriggerOutput {
        guard case .browsing(let q) = state else { return .passthrough }
        switch input {
        case .nameChar(let c):
            let next = q + String(c)
            state = .browsing(query: next)
            return TriggerOutput(action: .refreshBrowser(query: next), consumesKey: true)
        case .cancelChar(let c):
            // Spaces + punctuation are valid in emoji labels ("smiling face").
            let next = q + String(c)
            state = .browsing(query: next)
            return TriggerOutput(action: .refreshBrowser(query: next), consumesKey: true)
        case .colon:
            let next = q + ":"
            state = .browsing(query: next)
            return TriggerOutput(action: .refreshBrowser(query: next), consumesKey: true)
        case .backspace:
            if q.isEmpty {
                state = .idle
                return TriggerOutput(action: .closeBrowser, consumesKey: true)
            }
            let next = String(q.dropLast())
            state = .browsing(query: next)
            return TriggerOutput(action: .refreshBrowser(query: next), consumesKey: true)
        case .escape:
            state = .idle
            return TriggerOutput(action: .closeBrowser, consumesKey: true)
        case .returnKey, .tabKey:
            state = .idle
            return TriggerOutput(action: .pickBrowser, consumesKey: true)
        case .arrowUp:
            return TriggerOutput(action: .moveBrowser(direction: .up), consumesKey: true)
        case .arrowDown:
            return TriggerOutput(action: .moveBrowser(direction: .down), consumesKey: true)
        case .arrowLeft:
            return TriggerOutput(action: .moveBrowser(direction: .left), consumesKey: true)
        case .arrowRight:
            return TriggerOutput(action: .moveBrowser(direction: .right), consumesKey: true)
        case .focusChange:
            state = .idle
            return TriggerOutput(action: .closeBrowser, consumesKey: false)
        case .cmdZ:
            state = .idle
            return TriggerOutput(action: .closeBrowser, consumesKey: false)
        }
    }

    /// Fire if `idleWord` is a complete ambient that needs no terminator.
    /// When a strictly-longer key also matches the buffer, hold the fire
    /// in `pendingImmediateFire` so the next keystroke gets the chance to
    /// reach the longer match.
    private mutating func checkImmediateAmbientFire() -> TriggerOutput? {
        // Arrows match as a trailing suffix of the buffer, so they fire flush
        // against text (`Foo->Bar`) — the matched key is what gets deleted, so
        // the preceding `Foo` survives. Deferral (`<-` → `<->`) carries over.
        if arrowConversionEnabled,
           let arrow = AmbientEmoticonTable.arrowSuffix(of: idleWord),
           let emoji = AmbientEmoticonTable.emoji(for: arrow) {
            if AmbientEmoticonTable.hasLongerArrow(extending: arrow) {
                pendingImmediateFire = (word: arrow, emoji: emoji)
                return nil
            }
            idleWord = ""
            lastIdleKeystrokeAt = nil
            pendingImmediateFire = nil
            return TriggerOutput(
                action: .insertAmbientEmoticon(word: arrow, trailing: ""),
                consumesKey: false
            )
        }
        // Every other punctuation-led emoticon (`<3`, `</3`, `>:)`, …) still
        // requires the whole buffer to *be* the emoticon — i.e. a leading word
        // boundary — so it can't eat into prose (`Hi<3` stays literal). Arrows
        // are excluded here: when the toggle is on they're handled above; when
        // off they must stay literal even though they're punctuation-led.
        guard AmbientEmoticonTable.shouldFireImmediately(idleWord),
              !AmbientEmoticonTable.isArrow(idleWord) else {
            return nil
        }
        let word = idleWord
        idleWord = ""
        lastIdleKeystrokeAt = nil
        pendingImmediateFire = nil
        return TriggerOutput(
            action: .insertAmbientEmoticon(word: word, trailing: ""),
            consumesKey: false
        )
    }

    /// Resolve a pending deferred fire against an incoming idle char. If
    /// the char extends the pending toward a longer table entry, returns
    /// `nil` and the caller continues normal accumulation. Otherwise the
    /// pending fires now, consuming `c` and carrying it as `trailing` so
    /// the engine can re-emit it after the inserted emoji.
    private mutating func resolvePendingFire(with c: Character) -> TriggerOutput? {
        guard let pending = pendingImmediateFire else { return nil }
        let combined = pending.word + String(c)
        // Deferred matches are always arrows; keep accumulating only if this
        // char completes a longer arrow or still leads toward one.
        let extendsToward = AmbientEmoticonTable.arrowKeys.contains(combined)
            || AmbientEmoticonTable.hasLongerArrow(extending: combined)
        if extendsToward { return nil }
        let word = pending.word
        pendingImmediateFire = nil
        idleWord = ""
        lastIdleKeystrokeAt = nil
        return TriggerOutput(
            action: .insertAmbientEmoticon(word: word, trailing: String(c)),
            consumesKey: true
        )
    }
}
