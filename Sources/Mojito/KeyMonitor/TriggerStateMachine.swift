import Foundation

enum TriggerState: Equatable {
    case idle
    case capturing(query: String)
}

/// Whether the current capture searches the full corpus (`:foo`) or only
/// the experimental Symbols set (`::foo`, only reachable when
/// `symbolsRequireDoubleColon` is enabled).
enum CaptureScope: Equatable {
    case normal
    case symbolsOnly
}

enum TriggerInput {
    /// Printable name character (a–z, 0–9, _, -, +).
    case nameChar(Character)
    case backspace
    case colon         // `:`
    case escape
    case returnKey
    case tabKey
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    /// Anything not a name char that ends capture. Carries the actual char
    /// so Engine can check it against the emoticon table.
    case cancelChar(Character)
    case focusChange
    /// Cmd+Z (no other modifiers). Routed through the state machine so the
    /// Engine can undo a just-inserted emoticon. Falls through to passthrough
    /// when there's no recent emoticon to revert.
    case cmdZ
}

/// Output of the state machine: an action to take, plus whether the originating key
/// should be consumed (true) or allowed through to the focused app (false).
///
/// **Important design choice:** during capture, the `:` and the name characters the user
/// types are passed through to the focused app — they appear in the text field as the user
/// types them. Only when we actually insert an emoji do we delete the typed `:query` and
/// replace it. This means typing `:` literally (e.g. "9:00 PM") just works: if the user
/// types a non-name character afterward, capture cancels and the `:` stays.
struct TriggerOutput: Equatable {
    let action: TriggerAction
    let consumesKey: Bool

    static let passthrough = TriggerOutput(action: .none, consumesKey: false)
    static let consume = TriggerOutput(action: .none, consumesKey: true)
}

enum InsertMode: Equatable {
    /// User pressed Return / Tab — use whatever the picker has selected.
    /// Includes the easter-egg row and the random row.
    case fromPicker
    /// User typed the closing `:` — only insert if the query exactly matches
    /// a shortcode (or one of the special words `mojito` / `random`). If
    /// nothing matches, leave the typed `:query:` in the focused app untouched.
    case exactMatch
}

enum TriggerAction: Equatable {
    case none
    case openPicker(query: String, scope: CaptureScope)
    case refreshPicker(query: String, scope: CaptureScope)
    case closePicker
    case moveSelection(delta: Int)
    /// Delete the user's `:query` (or `:query:` for exactMatch) from the text
    /// field and insert the resolved emoji, if any. `scope` tells Engine
    /// which corpus to consult and how many leading colons to delete.
    case insertEmoji(query: String, mode: InsertMode, scope: CaptureScope)
    /// Cancel-char received during capture. Engine closes the picker and
    /// then checks whether `:query<terminator>` matches an emoticon. The
    /// terminator has been passed through to the focused app (consumesKey
    /// stays false), so by the time Engine acts the text reads `:query<c>`.
    /// Emoticons are an emoji feature — never fires in symbols-only scope.
    case checkEmoticon(query: String, terminator: Character)
    /// User typed too slowly to consider this an emoticon attempt — the
    /// `:query` typed plus the terminator should be left in place verbatim.
    /// Engine uses this signal to (a) close the picker, (b) NOT attempt an
    /// emoticon replacement, and (c) NOT register an undo window. The
    /// terminator was passed through, so the focused app already shows
    /// `:query<c>` — no edits needed.
    case abortEmoticon
    /// Engine should undo the most recent emoticon insertion if one is
    /// available within the undo window. If not, Engine does nothing and
    /// the caller (state machine) will have let the keystroke pass through.
    case maybeUndoEmoticon
    /// User entered the Konami code (↑↑↓↓←→←→BA). Fires the moment the
    /// final `A` is matched — no closing `:` required. `deleteCount` is the
    /// number of characters Engine needs to delete from the focused app's
    /// text field. Currently always 0 because every input in the sequence
    /// (arrows + B + A) is consumed before reaching the field.
    case triggerKonami(deleteCount: Int)
    /// Ambient emoticon candidate — the user typed a word (no leading `:`)
    /// followed by a terminator (space, period, etc.) and the state machine
    /// is asking Engine to look the word up in `AmbientEmoticonTable`. The
    /// terminator was passed through to the focused app (`consumesKey: false`).
    /// Engine no-ops if there's no match; otherwise it deletes
    /// `word.count + 1` chars and replaces with `emoji + terminator`.
    case checkAmbientEmoticon(word: String, terminator: Character)
    /// Ambient emoticon fired without a terminator — the word itself is the
    /// complete match (e.g. `<3`, `>:)`). The last char of the word was just
    /// typed and passed through (`consumesKey: false`); Engine deletes
    /// `word.count` chars and replaces with the emoji.
    case insertAmbientEmoticon(word: String)
}

struct TriggerStateMachine {
    var state: TriggerState = .idle

    /// Configured by Engine from `PrefsKey.symbolsRequireDoubleColon`. When true,
    /// typing `:` immediately after the opening `:` (i.e. `::`) switches the
    /// current capture into symbols-only scope instead of cancelling.
    var symbolsDoubleColonEnabled: Bool = false

    /// Scope of the current capture. Reset to `.normal` whenever capture starts.
    private var currentScope: CaptureScope = .normal

    /// How many steps of the Konami code have been matched in the current
    /// empty-query capture. Reset to 0 on capture start, on mismatch, or on
    /// exit from empty-query state. Triggers payoff when reaches
    /// `konamiSequence.count` and a closing `:` arrives.
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

    // True if the most recent idle keystroke landed the caret right after a letter/digit/etc.
    // Used to gate `:` triggers — capture only starts at word boundaries so typing "5:35" or
    // "foo:bar" doesn't fire the picker. Conservatively false after backspace, arrows, focus
    // changes, etc. so the picker still opens after non-typing caret motion.
    private var lastWasWordChar: Bool = false

    // The query that was being captured when the user dismissed via a non-Esc cancel char
    // (space, period, etc.). If they immediately backspace, we re-open the picker with that
    // query — the `:foo` text is still in the field, it's just behind the space they typed.
    // Cleared by Esc, focus change, insertion, any non-backspace idle keystroke, or a new `:`.
    private var revivableQuery: String? = nil

    /// Wall-clock time of the most recent keystroke within the current capture
    /// (set on `:` entry and on every name char). Used by `cancelChar` to
    /// decide whether the user's pause was too long to be considered an
    /// emoticon attempt — see `emoticonMaxIdle`.
    private var lastCaptureKeystrokeAt: Date? = nil

    /// Max seconds allowed between the previous keystroke in a capture and
    /// the terminator before we treat the typed text as not-an-emoticon and
    /// leave it alone.
    private static let emoticonMaxIdle: TimeInterval = 1.0

    /// Buffer of chars typed in `.idle` since the last terminator. Drives
    /// ambient emoticon detection (e.g. `<3 `, `XD `, `>:) `). Reset on
    /// terminator (after a lookup), focus change, arrow keys, escape,
    /// return/tab, colon entering capture, and after `emoticonMaxIdle` of
    /// keyboard silence.
    private var idleWord: String = ""

    /// Wall-clock time of the most recent keystroke that contributed to
    /// `idleWord`. Mirrors `lastCaptureKeystrokeAt` for the colon path.
    private var lastIdleKeystrokeAt: Date? = nil

    /// Word-terminator chars for ambient detection. Whitespace + sentence
    /// punctuation. Closing brackets like `)` are deliberately *not* here —
    /// they're part of emoticons (`B)`, `>:)`).
    private static let ambientTerminators: Set<Character> = [
        " ", "\t", "\n", ".", ",", ";", "!", "?",
    ]

    mutating func handle(_ input: TriggerInput) -> TriggerOutput {
        // Drop a stale ambient word if the user paused too long since the last
        // contributing keystroke. Same threshold as the colon-emoticon idle
        // check — covers click-to-move-caret followed by a delayed type.
        if let last = lastIdleKeystrokeAt,
           Date().timeIntervalSince(last) > Self.emoticonMaxIdle {
            idleWord = ""
            lastIdleKeystrokeAt = nil
        }

        let output = process(input)
        // After processing, refresh word-boundary tracking when we end up idle.
        if case .idle = state {
            switch input {
            case .nameChar: lastWasWordChar = true
            default:        lastWasWordChar = false
            }
            lastCaptureKeystrokeAt = nil
        } else {
            // Still capturing — record the time of this keystroke for the
            // emoticon-idle check on a future terminator. We update on every
            // input (colon-start, name chars) so the >1s window is measured
            // against the *most recent* keystroke, not the opening colon.
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
        // Konami code: tracked only in `.capturing(query: "")` — i.e.
        // after the user has typed an opening `:` but before any name
        // chars. Doing it from idle would eat arrow keys globally and
        // break ordinary caret navigation. Firing on the final `A` — no
        // closing `:` required.
        if case .capturing(let q) = state, q.isEmpty {
            // Match next step in sequence → consume input, advance.
            if konamiProgress < Self.konamiSequence.count,
               Self.konamiMatches(input, Self.konamiSequence[konamiProgress]) {
                konamiProgress += 1
                NSLog("[mojito] konami: step \(konamiProgress)/\(Self.konamiSequence.count) matched")
                // Fired the last step → run payoff immediately. Each input
                // in the sequence was consumed, so only the opening `:`
                // needs to be cleaned up from the focused app.
                if konamiProgress == Self.konamiSequence.count {
                    NSLog("[mojito] konami: sequence complete; firing payoff")
                    state = .idle
                    konamiProgress = 0
                    currentScope = .normal
                    return TriggerOutput(action: .triggerKonami(deleteCount: 1), consumesKey: true)
                }
                return .consume
            }
            // Mismatch → reset progress; fall through to normal handling.
            konamiProgress = 0
        } else {
            // Any non-empty capture or any idle state — Konami can't be active.
            konamiProgress = 0
        }

        switch (state, input) {

        // MARK: Cmd+Z — undo most recent emoticon insertion if one is fresh.
        // Must come before the catch-all `(.idle, _)` below.

        case (.idle, .cmdZ):
            // Engine decides whether to actually undo (depends on whether
            // there's a pending emoticon-undo entry within the window).
            // Drop the ambient buffer — Cmd+Z is a context-switching action.
            idleWord = ""
            lastIdleKeystrokeAt = nil
            return TriggerOutput(action: .maybeUndoEmoticon, consumesKey: false)

        case (.capturing, .cmdZ):
            // Mid-capture Cmd+Z: don't interfere; pass through. Engine won't
            // see an undo entry while a capture is in progress anyway.
            return .passthrough

        // MARK: idle

        case (.idle, .colon):
            revivableQuery = nil
            // Ambient prefix carve-out: if idleWord is exactly one of the
            // known "starts an ambient emoticon containing `:`" prefixes
            // (currently just `>`), let the colon continue the ambient word
            // instead of starting colon-capture. Otherwise `>:)` would be
            // intercepted by the colon path and only `:)` would convert,
            // leaving the `>` behind.
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
                // Right after a letter/digit (e.g. "5:35", "foo:bar") — don't trigger; pass through.
                return .passthrough
            }
            // Begin capture. Let the `:` pass through — it appears in the text field.
            currentScope = .normal
            state = .capturing(query: "")
            return TriggerOutput(action: .none, consumesKey: false)

        case (.idle, .backspace):
            // Keep the ambient buffer in sync with the field — drop the last
            // char if there's anything there.
            if !idleWord.isEmpty {
                idleWord = String(idleWord.dropLast())
                lastIdleKeystrokeAt = idleWord.isEmpty ? nil : Date()
            }
            // Revival: user typed `:foo<cancel-char>`, then backspaced the cancel char back
            // off. The `:foo` is still in the focused app — re-open the picker.
            // Revival is normal-scope only (we don't track scope across cancel).
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
                // Terminator — check the accumulated word against the ambient
                // table, then reset. Empty word means there was nothing to
                // match (e.g. two terminators in a row); no need to ask Engine.
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
            // Non-terminator punctuation (`<`, `>`, `)`, `(`, `_`, etc.) —
            // part of an emoticon body. Append and keep accumulating.
            idleWord += String(c)
            lastIdleKeystrokeAt = Date()
            if let fire = checkImmediateAmbientFire() {
                return fire
            }
            return .passthrough

        case (.idle, _):
            // Arrows, focus change, escape, return/tab in idle — all caret-
            // motion-y or context-switching. Drop the buffer.
            revivableQuery = nil
            idleWord = ""
            lastIdleKeystrokeAt = nil
            return .passthrough

        // MARK: capturing — colon

        case (.capturing(let q), .colon) where q.isEmpty:
            if symbolsDoubleColonEnabled, currentScope == .normal {
                // `::` → upgrade this capture to symbols-only. The second
                // colon passes through; picker stays empty until a name char.
                currentScope = .symbolsOnly
                return TriggerOutput(action: .none, consumesKey: false)
            }
            // Otherwise: `::` cancels. Both colons stay in text.
            state = .idle
            currentScope = .normal
            return TriggerOutput(action: .closePicker, consumesKey: false)

        case (.capturing(let q), .colon):
            // Closing `:` — let the colon pass through to the focused app so
            // the text reads `:query:`. Engine will delete the whole span
            // only when an exact match resolves; otherwise the typed text
            // stays as-is (no surprise replacement on near-misses).
            let scope = currentScope
            state = .idle
            currentScope = .normal
            return TriggerOutput(action: .insertEmoji(query: q, mode: .exactMatch, scope: scope), consumesKey: false)

        // MARK: capturing — name characters

        case (.capturing(let q), .nameChar(let c)):
            let next = q + String(c)
            state = .capturing(query: next)
            // Pass the character through so it appears in the text field.
            let threshold = pickerThreshold(for: currentScope)
            let action: TriggerAction
            if next.count < threshold {
                // Below threshold — keep capturing silently so a terminator can still
                // fire a colon emoticon (e.g. `:D `), but don't surface the picker.
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
                // Empty-query backspace. If we're in symbols scope (`::`),
                // demote back to normal scope (`:`) and let the backspace
                // delete the second colon. From normal scope, go fully idle.
                if currentScope == .symbolsOnly {
                    currentScope = .normal
                    return TriggerOutput(action: .closePicker, consumesKey: false)
                }
                state = .idle
                return TriggerOutput(action: .closePicker, consumesKey: false)
            }
            let next = String(q.dropLast())
            state = .capturing(query: next)
            // Let the backspace through; refresh picker, or close it if the
            // remaining query is empty or has dropped below the threshold.
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
            // While picker is up, eat ← / → so the caret can't drift out of `:query`.
            // Empty-query state means we just typed `:` and nothing else — let the arrow
            // through and end capture in that edge case.
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
            // Explicit dismiss — clear revival so a later backspace doesn't bring the picker back.
            revivableQuery = nil
            state = .idle
            currentScope = .normal
            return TriggerOutput(action: .closePicker, consumesKey: true)

        case (.capturing(let q), .cancelChar(let c)):
            // Don't set revivableQuery here — if the cancel char triggers an
            // emoticon replacement, the typed `:query` will be gone, and
            // reviving the picker with the same query would target stale
            // text. Worst case: the user types `:foo `, sees no replacement,
            // backspaces, and has to re-type `:foo`. Rare enough that the
            // tradeoff is worth keeping emoticons clean.
            //
            // In symbols-only scope, skip the emoticon check entirely (it's
            // an emoji feature) — just close.
            revivableQuery = nil
            let wasSymbolsOnly = currentScope == .symbolsOnly
            let lastAt = lastCaptureKeystrokeAt
            state = .idle
            currentScope = .normal
            if wasSymbolsOnly {
                return TriggerOutput(action: .closePicker, consumesKey: false)
            }
            // WEL-54: if too long has passed since the last keystroke in the
            // capture, treat this as not-an-emoticon — the user paused
            // mid-sentence, the terminator is just a normal cancel char.
            if let lastAt, Date().timeIntervalSince(lastAt) > Self.emoticonMaxIdle {
                return TriggerOutput(action: .abortEmoticon, consumesKey: false)
            }
            return TriggerOutput(action: .checkEmoticon(query: q, terminator: c), consumesKey: false)

        case (.capturing, .focusChange):
            // Focus change: the `:foo` text is now in a different context. Don't try to revive.
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
    }

    /// Minimum query length before the picker opens. Suppresses the briefly-
    /// visible single-letter picker (e.g. when typing `:D ` for 😃, or `:s`
    /// before `:smile:`). Symbols-only scope keeps the 1-char threshold
    /// because the symbols corpus is dominated by single-char entries.
    private func pickerThreshold(for scope: CaptureScope) -> Int {
        scope == .symbolsOnly ? 1 : 2
    }

    /// Returns an immediate-fire output if the current `idleWord` is a
    /// complete ambient emoticon that should fire without waiting for a
    /// terminator. Clears `idleWord` as a side effect when firing.
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
