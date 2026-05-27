import Foundation

enum TriggerState: Equatable {
    case idle
    case capturing(query: String)
    /// Active while the GIF picker is up. Consumes keystrokes and forwards
    /// them to the picker's view model via `.refreshGifPicker`, so typing
    /// after `:::` lands in the GIF search box (not the focused app).
    case gifSearching(query: String)
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
    /// Engine deletes `word.count` and replaces with the emoji.
    case insertAmbientEmoticon(word: String)
    /// User typed `:::` (three colons within `gifTripleColonWindow`).
    /// Engine deletes `deleteCount` chars (the 3 colons already typed)
    /// and opens the GIF search panel.
    case openGifPicker(deleteCount: Int)
    /// Updated GIF search query — Engine writes to the picker's view model.
    case refreshGifPicker(query: String)
    /// Close the GIF picker (esc, click-away, focus change).
    case closeGifPicker
    /// Enter pressed inside the GIF picker — copy the selected GIF.
    case pickGif
    /// Arrow-key navigation across the GIF grid.
    case moveGifSelection(direction: GifMoveDirection)
}

enum GifMoveDirection: Equatable { case left, right, up, down }

struct TriggerStateMachine {
    var state: TriggerState = .idle

    /// When true, `::` upgrades the capture to symbols-only instead of cancelling.
    var symbolsDoubleColonEnabled: Bool = false

    private var currentScope: CaptureScope = .normal

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

    /// Query in flight when capture ended via a non-Esc cancel char. If the
    /// user immediately backspaces, we re-open with this query — the `:foo`
    /// is still in the field, just behind the space they typed.
    private var revivableQuery: String? = nil

    /// Used by `cancelChar` to compare against `emoticonMaxIdle`.
    private var lastCaptureKeystrokeAt: Date? = nil

    private static let emoticonMaxIdle: TimeInterval = 1.0

    /// Chars typed in `.idle` since the last terminator. Drives ambient
    /// emoticon detection (`<3 `, `XD `, `>:) `).
    private var idleWord: String = ""

    private var lastIdleKeystrokeAt: Date? = nil

    /// Sliding window of recent colon timestamps used to detect `:::`
    /// (the GIF-search trigger) regardless of the current capture state.
    private var recentColonTimes: [Date] = []
    private static let gifTripleColonWindow: TimeInterval = 0.6

    /// Closing brackets like `)` are deliberately absent — they're part of
    /// emoticons (`B)`, `>:)`).
    private static let ambientTerminators: Set<Character> = [
        " ", "\t", "\n", ".", ",", ";", "!", "?",
    ]

    mutating func handle(_ input: TriggerInput) -> TriggerOutput {
        // Drop a stale ambient word after too long a pause (covers
        // click-to-move-caret followed by delayed typing).
        if let last = lastIdleKeystrokeAt,
           Date().timeIntervalSince(last) > Self.emoticonMaxIdle {
            idleWord = ""
            lastIdleKeystrokeAt = nil
        }

        let output = process(input)
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
                lastCaptureKeystrokeAt = Date()
            default:
                break
            }
        }
        return output
    }

    private mutating func process(_ input: TriggerInput) -> TriggerOutput {
        // While the GIF picker is showing, the state machine owns the
        // keyboard — namechars + arrows + enter + esc + backspace are
        // forwarded to the picker view model and consumed so they don't
        // double-feed into the focused app underneath.
        if case .gifSearching = state {
            return handleGifSearching(input)
        }

        // `:::` within `gifTripleColonWindow` opens the GIF picker no
        // matter what the capture state is. Runs before everything else
        // so it overrides the normal colon flow.
        if case .colon = input {
            let now = Date()
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
                revivableQuery = nil
                return TriggerOutput(action: .openGifPicker(deleteCount: 3), consumesKey: false)
            }
        } else {
            recentColonTimes.removeAll()
        }

        // Konami only runs in `.capturing(query: "")` (right after `:`).
        // Tracking it from idle would eat arrow keys globally and break
        // caret navigation. Fires on the final `A` — no closing `:`.
        if case .capturing(let q) = state, q.isEmpty {
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

        // `.gifSearching` is handled by the early-return guard above; this
        // branch is unreachable but required for exhaustiveness.
        case (.gifSearching, _):
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
            revivableQuery = nil
            // Carve-out so `>:)` etc. survive: if the colon-continuation
            // prefix is in the buffer (currently just `>`), append the
            // colon to the ambient word instead of starting capture —
            // otherwise the colon path would convert `:)` and leave `>`
            // behind.
            if AmbientEmoticonTable.colonContinuationPrefixes.contains(idleWord) {
                idleWord += ":"
                lastIdleKeystrokeAt = Date()
                if let fire = checkImmediateAmbientFire() {
                    return fire
                }
                return TriggerOutput(action: .none, consumesKey: false)
            }
            idleWord = ""
            lastIdleKeystrokeAt = nil
            if lastWasWordChar {
                // "5:35" / "foo:bar" — don't trigger.
                return .passthrough
            }
            currentScope = .normal
            state = .capturing(query: "")
            return TriggerOutput(action: .none, consumesKey: false)

        case (.idle, .backspace):
            if !idleWord.isEmpty {
                idleWord = String(idleWord.dropLast())
                lastIdleKeystrokeAt = idleWord.isEmpty ? nil : Date()
            }
            // Revival: user typed `:foo<cancel>`, then backspaced the
            // cancel back off. `:foo` is still in the field; re-open the
            // picker. Normal-scope only (scope isn't tracked across cancel).
            if let q = revivableQuery, !q.isEmpty {
                revivableQuery = nil
                currentScope = .normal
                state = .capturing(query: q)
                return TriggerOutput(action: .refreshPicker(query: q, scope: .normal), consumesKey: false)
            }
            return .passthrough

        case (.idle, .nameChar(let c)):
            revivableQuery = nil
            idleWord += String(c)
            lastIdleKeystrokeAt = Date()
            if let fire = checkImmediateAmbientFire() {
                return fire
            }
            return .passthrough

        case (.idle, .cancelChar(let c)):
            revivableQuery = nil
            if Self.ambientTerminators.contains(c) {
                // Terminator — look up the buffered word, then reset.
                let word = idleWord
                idleWord = ""
                lastIdleKeystrokeAt = nil
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
            lastIdleKeystrokeAt = Date()
            if let fire = checkImmediateAmbientFire() {
                return fire
            }
            return .passthrough

        case (.idle, _):
            // Arrows / focus change / escape / return/tab in idle — caret
            // motion or context switch. Drop the buffer.
            revivableQuery = nil
            idleWord = ""
            lastIdleKeystrokeAt = nil
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
            let next = q + String(c)
            state = .capturing(query: next)
            let threshold = pickerThreshold(for: currentScope)
            let action: TriggerAction
            if next.count < threshold {
                // Keep capturing silently so a terminator can still fire
                // `:D `, but don't surface the picker on a single char.
                action = .none
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
            let threshold = pickerThreshold(for: currentScope)
            let action: TriggerAction = next.count < threshold
                ? .closePicker
                : .refreshPicker(query: next, scope: currentScope)
            return TriggerOutput(action: action, consumesKey: false)

        // MARK: capturing — picker navigation

        case (.capturing(let q), .arrowUp):
            return q.isEmpty
                ? .passthrough
                : TriggerOutput(action: .moveSelection(delta: -1), consumesKey: true)

        case (.capturing(let q), .arrowDown):
            return q.isEmpty
                ? .passthrough
                : TriggerOutput(action: .moveSelection(delta: 1), consumesKey: true)

        case (.capturing(let q), .arrowLeft), (.capturing(let q), .arrowRight):
            // Eat ← / → so the caret can't drift out of `:query` while
            // the picker is up. Empty-query state is just `:` alone — let
            // the arrow through and end capture.
            if q.isEmpty {
                state = .idle
                return TriggerOutput(action: .closePicker, consumesKey: false)
            }
            return .consume

        case (.capturing(let q), .returnKey), (.capturing(let q), .tabKey):
            if q.isEmpty {
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
            // Clear revival so a later backspace doesn't bring the picker back.
            revivableQuery = nil
            state = .idle
            currentScope = .normal
            return TriggerOutput(action: .closePicker, consumesKey: true)

        case (.capturing(let q), .cancelChar(let c)):
            // Don't set revivableQuery: if this triggers an emoticon
            // replacement, `:query` is gone and reviving would target
            // stale text. Worst case the user re-types `:foo` — rare.
            //
            // Symbols-only skips emoticons entirely (it's an emoji feature).
            revivableQuery = nil
            let wasSymbolsOnly = currentScope == .symbolsOnly
            let lastAt = lastCaptureKeystrokeAt
            state = .idle
            currentScope = .normal
            if wasSymbolsOnly {
                return TriggerOutput(action: .closePicker, consumesKey: false)
            }
            // Long pause before terminator → user was mid-sentence; this
            // isn't an emoticon attempt.
            if let lastAt, Date().timeIntervalSince(lastAt) > Self.emoticonMaxIdle {
                return TriggerOutput(action: .abortEmoticon, consumesKey: false)
            }
            return TriggerOutput(action: .checkEmoticon(query: q, terminator: c), consumesKey: false)

        case (.capturing, .focusChange):
            // `:foo` is in a different context now; don't revive.
            revivableQuery = nil
            state = .idle
            currentScope = .normal
            return TriggerOutput(action: .closePicker, consumesKey: false)
        }
    }

    mutating func reset() {
        state = .idle
        currentScope = .normal
        lastWasWordChar = false
        revivableQuery = nil
        konamiProgress = 0
        idleWord = ""
        lastIdleKeystrokeAt = nil
        lastCaptureKeystrokeAt = nil
        recentColonTimes.removeAll()
    }

    /// 2 chars so `:D` / `:s` don't briefly flash the picker. Symbols
    /// scope stays at 1 because its corpus is mostly single-char entries.
    private func pickerThreshold(for scope: CaptureScope) -> Int {
        scope == .symbolsOnly ? 1 : 2
    }

    /// Routes keystrokes into the GIF picker's view model. Every input is
    /// `consumesKey: true` so nothing leaks into the focused app while the
    /// picker has the floor.
    private mutating func handleGifSearching(_ input: TriggerInput) -> TriggerOutput {
        guard case .gifSearching(let q) = state else { return .passthrough }
        switch input {
        case .nameChar(let c):
            let next = q + String(c)
            state = .gifSearching(query: next)
            return TriggerOutput(action: .refreshGifPicker(query: next), consumesKey: true)
        case .colon:
            // Allow as a query char so quirky searches still go through.
            let next = q + ":"
            state = .gifSearching(query: next)
            return TriggerOutput(action: .refreshGifPicker(query: next), consumesKey: true)
        case .cancelChar(let c):
            // Space + punctuation are valid in GIF queries
            // ("spongebob imagination", "you're welcome").
            let next = q + String(c)
            state = .gifSearching(query: next)
            return TriggerOutput(action: .refreshGifPicker(query: next), consumesKey: true)
        case .backspace:
            if q.isEmpty {
                state = .idle
                return TriggerOutput(action: .closeGifPicker, consumesKey: true)
            }
            let next = String(q.dropLast())
            state = .gifSearching(query: next)
            return TriggerOutput(action: .refreshGifPicker(query: next), consumesKey: true)
        case .escape:
            state = .idle
            return TriggerOutput(action: .closeGifPicker, consumesKey: true)
        case .returnKey, .tabKey:
            state = .idle
            return TriggerOutput(action: .pickGif, consumesKey: true)
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

    /// Fire if `idleWord` is a complete ambient that needs no terminator.
    private mutating func checkImmediateAmbientFire() -> TriggerOutput? {
        guard AmbientEmoticonTable.shouldFireImmediately(idleWord) else {
            return nil
        }
        let word = idleWord
        idleWord = ""
        lastIdleKeystrokeAt = nil
        return TriggerOutput(action: .insertAmbientEmoticon(word: word), consumesKey: false)
    }
}
