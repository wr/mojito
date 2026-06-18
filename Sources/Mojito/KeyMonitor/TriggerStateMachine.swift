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

    /// The bare in-code default: emoji + gif only. Mirrors the old SM field
    /// defaults (`symbolsDoubleColonEnabled = false`, `quickAccessTrigger = nil`)
    /// so a `TriggerStateMachine()` constructed without `setConfig` behaves like
    /// it always has. The Engine enables symbols / quickAccess from prefs.
    private static let bareConfig: TriggerConfig = {
        var c = TriggerConfig.default
        c.symbols.enabled = false
        c.quickAccess.enabled = false
        return c
    }()

    /// The active trigger set. `setConfig` rebuilds the matcher alongside it.
    private(set) var config: TriggerConfig = TriggerStateMachine.bareConfig
    private var matcher = TriggerMatcher(config: TriggerStateMachine.bareConfig)

    mutating func setConfig(_ config: TriggerConfig) {
        self.config = config
        self.matcher = TriggerMatcher(config: config)
    }

    // MARK: capture lifecycle (meaningful only while `state == .capturing`)

    /// Opening-delimiter chars typed before the query starts (e.g. `[":"]`,
    /// `[":",":"]`). Non-empty means we're still resolving which trigger this
    /// is; cleared once a query char locks the capture (and on reset/idle).
    private var openBuffer: [Character] = []
    /// Which mode the live capture resolved to. Drives scope + insert lengths.
    private var capturedMode: TriggerMode = .emoji
    /// Length of the open string that opened this capture (1 for `:`, 2 for `::`).
    private var capturedOpenLen: Int = 0
    /// How many chars of the active mode's close string have matched so far
    /// (0 = not mid-close). Lets a multi-char close (`::`) accumulate.
    private var closeProgress: Int = 0

    /// Open length of the live capture — read by the Engine's global-hotkey
    /// browser entry, where the capture is still in `.capturing` and the typed
    /// `:`/`::` must be erased on pick.
    var captureOpenLen: Int { capturedOpenLen }

    /// Open/close lengths of the most recent `.insertEmoji` action. The action's
    /// associated values are deliberately left unchanged (tests pin their shape),
    /// so the Engine reads the delete spans from here right after `handle()`.
    /// Not cleared by `reset()` — the value must survive the same-tick reset the
    /// closing keystroke triggers, until the next insert overwrites it.
    private(set) var lastInsertOpenLen: Int = 1
    private(set) var lastInsertCloseLen: Int = 1

    /// True only for the `handle()` call that transitioned idle → capturing.
    /// The Engine snapshots focus/secure-field/exclusion off this instead of
    /// inspecting the raw input, so non-colon trigger opens snapshot too.
    private(set) var captureJustOpened: Bool = false

    /// When true, `::` upgrades the capture to symbols-only instead of cancelling.
    /// Thin shim over `config`: existing callers flip this to enable/disable the
    /// symbols trigger (open `::`, close `:`).
    var symbolsDoubleColonEnabled: Bool {
        get { config.symbols.enabled }
        set {
            var t = config.symbols
            t.open = "::"
            t.close = ":"
            t.enabled = newValue
            config.set(t)
            matcher = TriggerMatcher(config: config)
        }
    }

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
    /// pill (e.g. `?` → `:?`). `nil` disables it. Thin shim over `config`:
    /// setting it rewrites the quickAccess open to `:` + char (enabled); `nil`
    /// disables the quickAccess trigger.
    var quickAccessTrigger: Character? {
        get {
            let qa = config.quickAccess
            guard qa.enabled, qa.open.count == 2, qa.open.first == ":" else { return nil }
            return qa.open.last
        }
        set {
            var t = config.quickAccess
            if let c = newValue {
                t.open = ":" + String(c)
                t.enabled = true
            } else {
                t.enabled = false
            }
            config.set(t)
            matcher = TriggerMatcher(config: config)
        }
    }

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

    /// The active capture's scope. Read by the Engine's global-hotkey browser
    /// entry, which synthesizes a pick outside the normal action flow and needs
    /// to know whether the field holds `:query` or `::query`. Derived from the
    /// resolved mode — symbols is the only scope-bearing mode.
    var captureScope: CaptureScope { capturedMode == .symbols ? .symbolsOnly : .normal }

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
        let wasIdle: Bool = { if case .idle = state { return true } else { return false } }()

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
        // Flag the idle → capturing transition so the Engine can snapshot the
        // focused field/exclusion off the SM rather than the raw input.
        captureJustOpened = wasIdle && { if case .capturing = state { return true } else { return false } }()
        if case .idle = state {
            switch input {
            case .nameChar: lastWasWordChar = true
            default:        lastWasWordChar = false
            }
            lastCaptureKeystrokeAt = nil
            // Opening lifecycle fields are only meaningful mid-capture; clear
            // them whenever we settle back to idle so a later capture starts clean.
            openBuffer = []
            closeProgress = 0
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
            if gifColonRunFires, recentColonTimes.count >= 3 {
                recentColonTimes.removeAll()
                return enterGif()
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
                    return TriggerOutput(action: .triggerKonami(deleteCount: 1), consumesKey: true)
                }
                return .consume
            }
            konamiProgress = 0
        } else {
            konamiProgress = 0
        }

        // Opening phase: a capture whose query is still empty and whose
        // opening-delimiter buffer is unresolved. Trigger chars (`:`, name,
        // cancel) and backspace are routed through the matcher-driven opening
        // logic; everything else (arrows / escape / return / focus) falls to
        // the empty-query cases in the switch below, unchanged.
        if !openBuffer.isEmpty, case .capturing(let q) = state, q.isEmpty {
            if let c = Self.triggerChar(input) {
                return handleOpening(char: c, input: input, now: now)
            }
            if case .backspace = input {
                return handleOpeningBackspace()
            }
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
            // `:` isn't a trigger prefix in a colon-less custom config — leave
            // it literal (it may still be an emoticon body char downstream).
            guard matcher.isViablePrefix([":"]) else { return .passthrough }
            return beginOpening(char: ":", input: input, now: now)

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
            // A name char opens a capture only in a custom config whose trigger
            // starts with it (default emoji `:` never reaches here). Word-char
            // gating still applies so it can't fire mid-word.
            if !lastWasWordChar, matcher.isViablePrefix([c]) {
                idleWord = ""
                lastIdleKeystrokeAt = nil
                pendingImmediateFire = nil
                return beginOpening(char: c, input: input, now: now)
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
            // A punctuation trigger char (custom configs, e.g. gif `;`) opens a
            // capture before falling through to ambient/terminator handling.
            // Default has no such trigger, so this never fires there.
            if matcher.isViablePrefix([c]) {
                idleWord = ""
                lastIdleKeystrokeAt = nil
                pendingImmediateFire = nil
                return beginOpening(char: c, input: input, now: now)
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

        // MARK: capturing — colon (locked capture; opening colons are routed
        // to `handleOpening` above). A colon here is a close-string char.

        case (.capturing(let q), .colon):
            return handleCloseChar(":", query: q)

        // MARK: capturing — name characters

        case (.capturing(let q), .nameChar(let c)):
            // Pill quick-pick: while the pill is up, a digit 1–8 inserts that
            // row directly (`:?3` → 3rd emoji). Swallowed so it doesn't start
            // a search.
            if emptyPickerActive, let digit = c.wholeNumberValue,
               digit >= 1, digit <= min(8, pillEmojiCount) {
                return TriggerOutput(action: .pickIndex(digit - 1), consumesKey: true)
            }
            // A name char that is the next char of the close string (custom
            // configs whose close uses letters/digits) drives the close instead
            // of extending the query. Default close (`:`) never reaches here.
            if let close = closeChar(query: q), close == c {
                return handleCloseChar(c, query: q)
            }
            return appendQueryChar(c, query: q)

        // MARK: capturing — backspace

        case (.capturing(let q), .backspace):
            // Mid-close backspace peels one matched close char back off and
            // reopens the picker on the still-typed query.
            if closeProgress > 0 {
                closeProgress -= 1
                return TriggerOutput(action: .refreshPicker(query: q, scope: captureScope), consumesKey: false)
            }
            if q.isEmpty {
                // Locked capture with an empty query only happens for a 1-char
                // open (e.g. emoji `:`); backspacing the open char ends capture.
                state = .idle
                return TriggerOutput(action: .closePicker, consumesKey: false)
            }
            let next = String(q.dropLast())
            state = .capturing(query: next)
            let threshold = pickerThreshold(for: captureScope, query: next)
            let action: TriggerAction = next.count < threshold
                ? .closePicker
                : .refreshPicker(query: next, scope: captureScope)
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
                    // Pill insert: the typed open (`:` for default) is erased on pick.
                    lastInsertOpenLen = capturedOpenLen == 0 ? 1 : capturedOpenLen
                    lastInsertCloseLen = 0
                    return TriggerOutput(action: .insertEmoji(query: "", mode: .fromPicker, scope: .normal), consumesKey: true)
                }
                state = .idle
                return TriggerOutput(action: .closePicker, consumesKey: false)
            }
            let scope = captureScope
            state = .idle
            lastInsertOpenLen = capturedOpenLen
            lastInsertCloseLen = 0
            return TriggerOutput(action: .insertEmoji(query: q, mode: .fromPicker, scope: scope), consumesKey: true)

        // MARK: capturing — exits

        case (.capturing, .escape):
            // `:?`+Esc should leave the literal `:?` — the `?` was swallowed
            // when the pill opened, so ask the Engine to type it back.
            let restoreQuestion = emptyPickerActive && quickAccessTrigger != nil
            emptyPickerActive = false
            state = .idle
            return TriggerOutput(
                action: restoreQuestion ? .closePickerRestoringQuestion : .closePicker,
                consumesKey: true
            )

        case (.capturing(let q), .cancelChar(let c)):
            // A cancel char that is the next char of the close string closes the
            // capture (custom configs whose close is punctuation). Default close
            // is `:` (a `.colon`), so this never pre-empts emoticons there.
            if let close = closeChar(query: q), close == c {
                return handleCloseChar(c, query: q)
            }
            // Symbols-only skips emoticons entirely (it's an emoji feature).
            let wasSymbolsOnly = captureScope == .symbolsOnly
            let lastAt = lastCaptureKeystrokeAt
            state = .idle
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
        capturedMode = .emoji
        capturedOpenLen = 0
        openBuffer = []
        closeProgress = 0
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

    // MARK: - Opening / closing helpers

    /// The literal char an input contributes to a delimiter run, or nil for a
    /// control input (backspace/arrows/return/etc.).
    private static func triggerChar(_ input: TriggerInput) -> Character? {
        switch input {
        case .colon:           return ":"
        case .nameChar(let c): return c
        case .cancelChar(let c): return c
        default:               return nil
        }
    }

    /// True when the GIF trigger is a run of colons — those are detected by the
    /// rolling `recentColonTimes` window (so `::`-cancel can coexist with the
    /// `:::` open). A non-colon gif trigger (`;`) is opened positionally instead.
    private var gifColonRunFires: Bool {
        let gif = config.gif
        return gif.enabled && !gif.open.isEmpty && gif.open.allSatisfy { $0 == ":" }
    }

    /// Some active emoji/symbols/quickAccess open has `cand` as a strict prefix.
    /// GIF is excluded so a colon-run heading only toward `:::` doesn't keep the
    /// buffer alive (it must cancel, matching legacy `::`); the window handles gif.
    private func headsTowardNonGifTrigger(_ cand: [Character]) -> Bool {
        config.active.contains { t in
            guard t.mode != .gif else { return false }
            let open = Array(t.open)
            return open.count > cand.count && Array(open.prefix(cand.count)) == cand
        }
    }

    /// Begin a fresh capture from idle and resolve the first delimiter char.
    private mutating func beginOpening(char c: Character, input: TriggerInput, now: Date) -> TriggerOutput {
        state = .capturing(query: "")
        openBuffer = []
        closeProgress = 0
        capturedMode = .emoji
        capturedOpenLen = 0
        // Not visible yet — the Engine flips this on after the debounced show.
        emptyPickerActive = false
        return handleOpening(char: c, input: input, now: now)
    }

    /// Resolve a delimiter char while the capture's query is still empty.
    /// `openBuffer` holds the run so far (empty on the idle-entry call).
    private mutating func handleOpening(char c: Character, input: TriggerInput, now: Date) -> TriggerOutput {
        let cand = openBuffer + [c]

        // A fully-determined no-query trigger (gif / quickAccess) fires now.
        if let m = matcher.terminalMode(for: cand), m == .gif || m == .quickAccess, !matcher.canExtend(cand) {
            switch m {
            case .gif:
                return enterGif()
            case .quickAccess:
                // The trigger char is swallowed, so only the chars already in
                // the field (the buffer before this one) are erased on pick. The
                // pill is a terminal open — clear the buffer so the capture is
                // locked and following keys (digit pick / search) route normally.
                capturedMode = .quickAccess
                capturedOpenLen = openBuffer.count
                openBuffer = []
                return TriggerOutput(action: .openPicker(query: "", scope: .normal), consumesKey: true)
            default:
                break
            }
        }

        // A query-mode terminal (emoji / symbols): track it and keep building —
        // a longer open (or the symbols upgrade) may still extend the run.
        if let m = matcher.terminalMode(for: cand), m == .emoji || m == .symbols {
            openBuffer = cand
            capturedMode = m
            capturedOpenLen = cand.count
            return openingPassthrough()
        }

        // Still a viable prefix heading toward a longer emoji/symbols/quickAccess
        // open — keep accumulating the run.
        if matcher.isViablePrefix(cand), headsTowardNonGifTrigger(cand) {
            openBuffer = cand
            return openingPassthrough()
        }

        // Dead end. If the run so far is a usable query-mode open, lock it and
        // reprocess `c` as the first locked-capture input.
        if let m = matcher.terminalMode(for: openBuffer), m == .emoji || m == .symbols {
            capturedMode = m
            capturedOpenLen = openBuffer.count
            openBuffer = []
            return lockedCapture(input, query: "", now: now)
        }

        // The run never formed a usable trigger — abandon capture, leave text.
        state = .idle
        return .passthrough
    }

    /// Output for staying in the opening phase: nothing happens, but if the
    /// favorites pill was up (multi-char open mid-build) drop it.
    private mutating func openingPassthrough() -> TriggerOutput {
        if emptyPickerActive {
            emptyPickerActive = false
            return TriggerOutput(action: .closePicker, consumesKey: false)
        }
        return TriggerOutput(action: .none, consumesKey: false)
    }

    /// Transition into GIF search, clearing capture/ambient bookkeeping.
    private mutating func enterGif() -> TriggerOutput {
        state = .gifSearching(query: "")
        openBuffer = []
        closeProgress = 0
        konamiProgress = 0
        idleWord = ""
        lastIdleKeystrokeAt = nil
        pendingImmediateFire = nil
        recentColonTimes.removeAll()
        return TriggerOutput(action: .openGifPicker, consumesKey: false)
    }

    /// Backspace while still building the opening run: peel one delimiter char.
    /// Emptying the buffer ends the capture; otherwise re-resolve the mode the
    /// shorter run opens (so `::`→`:` demotes symbols back to emoji scope).
    private mutating func handleOpeningBackspace() -> TriggerOutput {
        openBuffer.removeLast()
        if openBuffer.isEmpty {
            state = .idle
            return TriggerOutput(action: .closePicker, consumesKey: false)
        }
        if let m = matcher.terminalMode(for: openBuffer), m == .emoji || m == .symbols {
            capturedMode = m
            capturedOpenLen = openBuffer.count
        }
        return TriggerOutput(action: .closePicker, consumesKey: false)
    }

    /// The active mode's close string, or nil for no-close modes.
    private func closeString() -> [Character]? {
        matcher.close(for: capturedMode)
    }

    /// The single close char expected next given `closeProgress`, or nil if the
    /// active mode has no close. Used by the locked nameChar/cancelChar cases to
    /// decide whether an incoming char drives the close.
    private func closeChar(query: String) -> Character? {
        guard !query.isEmpty, let close = closeString(), closeProgress < close.count else { return nil }
        return close[closeProgress]
    }

    /// Append a name char to a locked capture's query and surface/refresh/hold
    /// the picker per the threshold. Shared by the nameChar case and lock-reentry.
    private mutating func appendQueryChar(_ c: Character, query q: String) -> TriggerOutput {
        let wasEmptyPicker = emptyPickerActive
        emptyPickerActive = false
        let next = q + String(c)
        state = .capturing(query: next)
        let scope = captureScope
        let threshold = pickerThreshold(for: scope, query: next)
        let action: TriggerAction
        if next.count < threshold {
            // Keep capturing silently so a terminator can still fire `:D `, but
            // don't surface the picker on a single char. If favorites were
            // showing, close them as typing begins.
            action = wasEmptyPicker ? .closePicker : .none
        } else if q.count < threshold {
            action = .openPicker(query: next, scope: scope)
        } else {
            action = .refreshPicker(query: next, scope: scope)
        }
        return TriggerOutput(action: action, consumesKey: false)
    }

    /// Drive the multi-char close. `c` is known to be a close-string char (the
    /// caller checked) or a colon in a locked capture. Completing the close
    /// fires an exact-match insert; a partial match holds (the picker may drop);
    /// a mismatch aborts the close and leaves the text alone.
    private mutating func handleCloseChar(_ c: Character, query q: String) -> TriggerOutput {
        guard let close = closeString() else {
            // No close string — a stray delimiter is just a literal query char.
            // Reachable only for odd custom configs; default never hits.
            return appendQueryChar(c, query: q)
        }
        if q.isEmpty {
            // Close delimiter typed with no query to close (`::` for default
            // emoji) — cancel; both delimiters stay in the field as literal text.
            state = .idle
            closeProgress = 0
            return TriggerOutput(action: .closePicker, consumesKey: false)
        }
        if c == close[closeProgress] {
            closeProgress += 1
            if closeProgress == close.count {
                let scope = captureScope
                let openLen = capturedOpenLen
                let closeLen = close.count
                state = .idle
                lastInsertOpenLen = openLen
                lastInsertCloseLen = closeLen
                return TriggerOutput(action: .insertEmoji(query: q, mode: .exactMatch, scope: scope), consumesKey: false)
            }
            // Partial close: the char passes through; the picker may drop, which
            // is acceptable (it reopens if the close aborts via backspace).
            return TriggerOutput(action: .none, consumesKey: false)
        }
        // Mismatch after a partial close — abandon. Both the matched close chars
        // and this one stay in the field.
        closeProgress = 0
        state = .idle
        return .passthrough
    }

    /// Run the locked-capture transitions (`process`'s `(.capturing, …)` cases)
    /// for an input, used when the opening run locks and reprocesses its first
    /// query char. Mirrors the relevant switch arms.
    private mutating func lockedCapture(_ input: TriggerInput, query q: String, now: Date) -> TriggerOutput {
        switch input {
        case .colon:
            return handleCloseChar(":", query: q)
        case .nameChar(let c):
            if let close = closeChar(query: q), close == c {
                return handleCloseChar(c, query: q)
            }
            return appendQueryChar(c, query: q)
        case .cancelChar(let c):
            if quickAccessTrigger == c, q.isEmpty {
                // A locked-capture quickAccess char can only arise for an emoji
                // open shorter than `:` + trigger; handled as the pill open.
                return TriggerOutput(action: .openPicker(query: "", scope: .normal), consumesKey: true)
            }
            if let close = closeChar(query: q), close == c {
                return handleCloseChar(c, query: q)
            }
            let wasSymbolsOnly = captureScope == .symbolsOnly
            let lastAt = lastCaptureKeystrokeAt
            state = .idle
            if wasSymbolsOnly {
                return TriggerOutput(action: .closePicker, consumesKey: false)
            }
            if let lastAt, now.timeIntervalSince(lastAt) > Self.emoticonMaxIdle {
                return TriggerOutput(action: .abortEmoticon, consumesKey: false)
            }
            return TriggerOutput(action: .checkEmoticon(query: q, terminator: c), consumesKey: false)
        default:
            return .passthrough
        }
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
            // The gif open + query are all sitting in the focused app — delete
            // the full span so the GIF replaces the typed trigger.
            return TriggerOutput(action: .pickGif(deleteCount: q.count + config.gif.open.count), consumesKey: true)
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
