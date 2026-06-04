import AppKit
import Combine
import Foundation
import os.log

/// Wires KeyMonitor → state machine → picker → inserter.
@MainActor
final class Engine: ObservableObject, KeyMonitorDelegate {
    @Published private(set) var isActive: Bool = false
    @Published var pausedUntil: Date?

    /// State-machine label for diagnostic reports. Query contents are
    /// elided so the value is anonymous.
    var triggerStateLabel: String {
        switch stateMachine.state {
        case .idle:          return "idle"
        case .capturing:     return "capturing"
        case .gifSearching:  return "gifSearching"
        case .browsing:      return "browsing"
        }
    }

    private let database: EmojiDatabase
    private let exclusions: ExclusionStore
    private let quickAccess = QuickAccessStore.shared
    private let viewModel = PickerViewModel()
    private let pickerWindow: PickerWindow
    private let gifPickerWindow = GifPickerWindow()
    private let monitor = KeyMonitor()

    private var stateMachine = TriggerStateMachine()
    private var permissions: PermissionsCoordinator?
    private var permissionsObserver: AnyCancellable?

    private var captureContext: ActiveContext?
    /// Snapshot of the AX-focused element at `:` time. The picker shows one
    /// runloop tick later; if focus has moved, we cancel rather than render on
    /// the wrong window. Identity via `CFEqual` — same element, not similar.
    private var captureFocusSnapshot: AXUIElement?
    /// Fallback for when AX element identity can't be compared.
    private var captureFocusPID: pid_t?
    /// True if the current capture's app/URL is in the exclusion list.
    /// Emoji-related actions get suppressed; GIF picker still fires.
    private var captureIsExcluded: Bool = false
    private var usage: [String: Int]
    private var workspaceObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var prefsObserver: NSObjectProtocol?
    /// Cached because `FuzzyMatcher.search` reads them on every keystroke and
    /// direct UserDefaults reads are a measurable per-keystroke cost.
    private var useFrequencyBoost: Bool
    private var symbolsEnabled: Bool
    private var symbolsRequireDoubleColon: Bool
    private var gifSearchEnabled: Bool
    private var gifBypassExclusions: Bool

    /// Most-recent emoticon insertion still inside its undo window. Cleared on
    /// successful undo, timeout, focus change, any text-mutating keystroke,
    /// app switch, or shutdown.
    private var pendingEmoticonUndo: EmoticonUndo?
    /// Captured at dispatch time by deferred conversion handlers; if it has
    /// advanced when the handler fires, the user typed past us and we skip the
    /// undo entry.
    private var inputSeq: Int = 0
    /// `inputSeq` of the most recent digit keystroke. Lets the deferred heart
    /// insert skip itself when a digit lands immediately after (`<30`) before
    /// the conversion (and its undo entry) has even been created.
    private var lastDigitSeq: Int = -1
    private static let emoticonUndoWindow: TimeInterval = 3.0
    /// Chars of typed `:` to erase before a browser pick is synthesized
    /// (1 when opened from the pill's chevron, 0 from the menu).
    private var browserDeleteCount: Int = 0

    init(database: EmojiDatabase, exclusions: ExclusionStore) {
        self.database = database
        self.exclusions = exclusions
        self.pickerWindow = PickerWindow(viewModel: viewModel)
        self.usage = (UserDefaults.standard.dictionary(forKey: PrefsKey.usageCounts) as? [String: Int]) ?? [:]
        self.useFrequencyBoost = (UserDefaults.standard.object(forKey: PrefsKey.useFrequencyBoost) as? Bool) ?? true
        self.symbolsEnabled = (UserDefaults.standard.object(forKey: PrefsKey.symbolsEnabled) as? Bool) ?? false
        self.symbolsRequireDoubleColon = (UserDefaults.standard.object(forKey: PrefsKey.symbolsRequireDoubleColon) as? Bool) ?? false
        self.gifSearchEnabled = (UserDefaults.standard.object(forKey: PrefsKey.gifSearchEnabled) as? Bool) ?? true
        self.gifBypassExclusions = (UserDefaults.standard.object(forKey: PrefsKey.gifBypassExclusions) as? Bool) ?? true
        self.stateMachine.symbolsDoubleColonEnabled = self.symbolsEnabled && self.symbolsRequireDoubleColon
        // The pill is summoned by `:?` when Quick Access is enabled.
        let qaEnabled = (UserDefaults.standard.object(forKey: PrefsKey.quickAccessEnabled) as? Bool) ?? true
        self.stateMachine.quickAccessTrigger = qaEnabled ? "?" : nil
        // Arrows are inert unless both emoticons and the arrow sub-toggle are on
        // — gating in the SM means a disabled arrow never defers or consumes a
        // following char (which would otherwise be dropped when the insert is
        // suppressed downstream).
        self.stateMachine.arrowConversionEnabled = Engine.arrowConversionActive()

        // Click-away behaves like Esc but doesn't consume the click.
        pickerWindow.onClickAway = { [weak self] in
            self?.cancelCapture()
        }

        // Mouse-pick on a compact favorites-pill cell — same resolution path
        // as Return on the bar (insert the cell, or open Browse for the
        // chevron). Only fires while the empty-query pill is up.
        viewModel.onActivate = { [weak self] index in
            guard let self, self.viewModel.compact else { return }
            guard index < self.viewModel.results.count else { return }
            self.viewModel.selectedIndex = index
            if self.viewModel.results[index].emoji.hexcode == EmojiBrowser.sentinelHexcode {
                self.expandToBrowser(deleteCount: 1)  // the typed `:`
            } else {
                self.insert(query: "", mode: .fromPicker, scope: .normal)
            }
        }

        // Mouse pick / category tab inside the expanded grid.
        viewModel.onBrowserPick = { [weak self] emoji in
            guard let self else { return }
            self.viewModel.browser?.select(emoji)
            self.pickFromBrowser()
        }
        viewModel.onBrowserCategory = { [weak self] category in
            guard let self else { return }
            // Switching category clears any in-progress search, so keep the
            // state machine's browser query in sync.
            self.stateMachine.setBrowsingQuery("")
            self.viewModel.browser?.selectCategory(category)
        }

        gifPickerWindow.onClickAway = { [weak self] in
            self?.gifPickerWindow.hide()
            self?.stateMachine.reset()
        }

        gifPickerWindow.onPickClicked = { [weak self] in
            self?.stateMachine.reset()
        }

        gifPickerWindow.onGifInserted = { [weak self] in
            DebugRecorder.record(.gif, "insert")
            self?.recordGifInserted()
        }

        // Per-keystroke polling raced the picker's `orderFrontRegardless()`,
        // so we listen for real app switches instead.
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            MainActor.assumeIsolated {
                self?.handleAppActivated(notification: notif)
            }
        }

        // Switching Spaces (incl. into a fullscreen app) should dismiss any
        // open surface — the panel joins all Spaces, so without this the
        // browser/pill would linger on the new desktop.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.viewModel.isVisible || self.gifPickerWindow.isVisible else { return }
                self.cancelCapture()  // also hides the GIF picker
            }
        }

        // Spotlight, system panels, and in-app field jumps don't fire
        // didActivateApplicationNotification reliably — AX does, synchronously.
        FocusedElementCache.shared.onFocusChange = { [weak self] in
            MainActor.assumeIsolated {
                self?.handleFocusChanged()
            }
        }

        prefsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.useFrequencyBoost = (UserDefaults.standard.object(forKey: PrefsKey.useFrequencyBoost) as? Bool) ?? true
                self.symbolsEnabled = (UserDefaults.standard.object(forKey: PrefsKey.symbolsEnabled) as? Bool) ?? false
                self.symbolsRequireDoubleColon = (UserDefaults.standard.object(forKey: PrefsKey.symbolsRequireDoubleColon) as? Bool) ?? false
                self.gifSearchEnabled = (UserDefaults.standard.object(forKey: PrefsKey.gifSearchEnabled) as? Bool) ?? true
                self.gifBypassExclusions = (UserDefaults.standard.object(forKey: PrefsKey.gifBypassExclusions) as? Bool) ?? true
                self.stateMachine.symbolsDoubleColonEnabled = self.symbolsEnabled && self.symbolsRequireDoubleColon
                let qaEnabled = (UserDefaults.standard.object(forKey: PrefsKey.quickAccessEnabled) as? Bool) ?? true
                self.stateMachine.quickAccessTrigger = qaEnabled ? "?" : nil
                self.stateMachine.arrowConversionEnabled = Engine.arrowConversionActive()
            }
        }
    }

    /// Arrow conversion runs only when emoticons *and* the arrow sub-toggle are
    /// both on. Read fresh (cheap, off the keystroke path).
    private static func arrowConversionActive() -> Bool {
        let emoticonsOn = (UserDefaults.standard.object(forKey: PrefsKey.emoticonsEnabled) as? Bool) ?? true
        let arrowsOn = (UserDefaults.standard.object(forKey: PrefsKey.arrowConversionEnabled) as? Bool) ?? true
        return emoticonsOn && arrowsOn
    }

    deinit {
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        if let obs = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        if let obs = prefsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    private func handleAppActivated(notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        // Our own panel briefly looking frontmost is not a real app switch.
        if bundleID == Bundle.main.bundleIdentifier { return }
        pendingEmoticonUndo = nil
        switch stateMachine.state {
        case .capturing:
            guard bundleID != captureContext?.bundleID else { return }
            cancelCapture()
        case .browsing:
            // Close the browser when another app (incl. a fullscreen app)
            // takes over.
            cancelCapture()
        default:
            break
        }
    }

    private func handleFocusChanged() {
        pendingEmoticonUndo = nil
        // The browser owns the keyboard while open and a pick is synthesized
        // into whatever field is focused, so an AX focus change (in-app field
        // jump, Spotlight) means our target moved — dismiss it, exactly as a
        // capture does. Cross-app switches are handled by handleAppActivated.
        switch stateMachine.state {
        case .capturing:
            break
        case .browsing:
            // The browser can be opened over a no-focus context (e.g. the
            // Finder, to copy a glyph) — there's no captured field to drift
            // away from, so a stray focus change must not self-dismiss it.
            if captureFocusSnapshot == nil { return }
        default:
            return
        }
        guard let snapshot = captureFocusSnapshot else {
            cancelCapture()
            return
        }
        let cache = FocusedElementCache.shared
        if let currentPID = cache.focusedPID,
           let snapPID = captureFocusPID,
           currentPID != snapPID {
            cancelCapture()
            return
        }
        // CFEqual handles AX element equality across copies.
        if let current = cache.element, !CFEqual(snapshot, current) {
            cancelCapture()
        }
        // Nil current element = transient focus-transition state; wait for the next callback.
    }

    private func cancelCapture() {
        stateMachine.reset()
        viewModel.reset()
        pickerWindow.hide()
        gifPickerWindow.hide()
        clearCaptureState()
        DebugRecorder.record(.picker, "cancel")
    }

    /// Reset the per-capture bookkeeping (context, focused-field snapshot,
    /// excluded flag, browser delete count). Window + state-machine teardown is
    /// left to the caller — those differ per entry point.
    private func clearCaptureState() {
        captureContext = nil
        captureFocusSnapshot = nil
        captureFocusPID = nil
        captureIsExcluded = false
        browserDeleteCount = 0
    }

    func attach(permissions: PermissionsCoordinator) {
        self.permissions = permissions
        permissionsObserver = permissions.$accessibility
            .combineLatest(permissions.$inputMonitoring)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.reconcile() }
    }

    func start() {
        reconcile()
    }

    func stop() {
        monitor.stop()
        pickerWindow.hide()
        stateMachine.reset()
        captureContext = nil
        captureFocusSnapshot = nil
        captureFocusPID = nil
        pendingEmoticonUndo = nil
        isActive = false
    }

    func pause(until date: Date) {
        pausedUntil = date
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: PrefsKey.pausedUntil)
        DebugRecorder.record(.engine, "pause")
        reconcile()
    }

    func resume() {
        pausedUntil = nil
        UserDefaults.standard.removeObject(forKey: PrefsKey.pausedUntil)
        DebugRecorder.record(.engine, "resume")
        reconcile()
    }

    /// In-memory and on-disk must clear in lockstep, else the next insert
    /// writes the stale map back. Writes an empty dict rather than
    /// `removeObject` so the dev build's release-domain fallback (see
    /// main.swift) can't resurrect cleared counts.
    func clearUsageStats() {
        objectWillChange.send()
        usage = [:]
        UserDefaults.standard.set([String: Int](), forKey: PrefsKey.usageCounts)
        // Lifetime totals track milestone progress; they reset alongside
        // the per-emoji counts so "Clear stats" feels like a true reset.
        UserDefaults.standard.set(0, forKey: PrefsKey.totalEmojiInserted)
        UserDefaults.standard.set(0, forKey: PrefsKey.totalSymbolInserted)
        UserDefaults.standard.set(0, forKey: PrefsKey.totalGifInserted)
        UserDefaults.standard.set(0, forKey: PrefsKey.totalEmoticonInserted)
    }

    private func reconcile() {
        guard let permissions, permissions.allGranted else {
            stop()
            return
        }
        if let until = pausedUntil, until > Date() {
            stop()
            return
        }
        if !monitor.isRunning {
            monitor.delegate = self
            if monitor.start() {
                isActive = true
            }
        }
    }

    // MARK: - KeyMonitorDelegate

    nonisolated func keyMonitor(_ monitor: KeyMonitor, didReceive input: TriggerInput) -> Bool {
        MainActor.assumeIsolated { self.process(input: input) }
    }

    nonisolated func keyMonitorDidLoseTap(_ monitor: KeyMonitor) {
        MainActor.assumeIsolated {
            self.cancelCapture()
            // Tap may have died because the user revoked Input Monitoring —
            // let the coordinator resume polling and surface the UI state.
            self.permissions?.handleInputMonitoringLost()
        }
    }

    private func process(input: TriggerInput) -> Bool {
        inputSeq &+= 1
        if case .nameChar(let c) = input, c.isNumber { lastDigitSeq = inputSeq }
        // BSOD-style "press any key" effects pre-empt everything; the key is
        // consumed so it doesn't leak into the focused app underneath.
        if case .idle = stateMachine.state, EffectDismisser.topWantsAnyKey() {
            EffectDismisser.dismissTop()
            return true
        }

        // Only pre-empt Esc when idle so Esc-during-capture still cancels
        // the picker the normal way.
        if case .escape = input, case .idle = stateMachine.state,
           EffectDismisser.dismissTop() {
            return true
        }

        if case .idle = stateMachine.state, case .backspace = input,
           pendingEmoticonUndo != nil, performEmoticonUndoIfFresh() {
            return true
        }
        // Cmd+Z is intercepted here (not in the state machine) because the
        // consume decision depends on whether there's a fresh undo entry,
        // which the state machine doesn't track. No entry → pass through to
        // the focused app's normal undo.
        if case .cmdZ = input {
            if case .idle = stateMachine.state,
               pendingEmoticonUndo != nil, performEmoticonUndoIfFresh() {
                return true
            }
            return false
        }

        // `<3`→❤️ fires eagerly so a heart at the end of a message lands. If a
        // digit follows once the heart has rendered, the user meant a number
        // (`<30`): rebuild `<3` + the digit in one replacement and consume the
        // key, so the restore and the digit can't interleave (the race that
        // produced `❤️<3`). Faster follow-ups are caught by the skip in the
        // deferred insert, before the heart renders.
        if case .idle = stateMachine.state, case .nameChar(let c) = input, c.isNumber,
           let undo = pendingEmoticonUndo,
           AmbientEmoticonTable.revocableByTrailingDigit(undo.originalText),
           performEmoticonUndoIfFresh(appending: String(c)) {
            return true
        }

        // Any other keystroke closes the undo window. Otherwise the entry
        // persists across typing, and `TextInserter.replace` deletes from
        // the current caret (not the post-conversion one) — backspace after
        // `:) ` would delete the space and then *type* `:)` after the emoji
        // (`🙂 ` → `🙂:)`).
        pendingEmoticonUndo = nil

        // Secure-field check short-circuits — we never want to inspect a
        // password field. The exclusion list is honored per-action: emoji
        // picker / emoticon conversion are suppressed in excluded apps,
        // but the GIF picker (`:::`) still fires so a user can excise
        // Slack's native emoji UI without losing GIF search there.
        if case .idle = stateMachine.state, case .colon = input {
            let context = AppContextDetector.current()
            if context.focusedFieldIsSecure {
                DebugRecorder.record(.engine, "secureFieldBlocked")
                return false
            }
            captureContext = context
            captureIsExcluded = exclusions.isExcluded(bundleID: context.bundleID, url: context.url)
            DebugRecorder.record(.engine, "colon", [
                "excluded": "\(captureIsExcluded)",
                "hasURL": "\(context.url != nil)",
            ])
            // Snapshot now so the deferred picker show and any focus-change
            // notifications can detect movement out from under us.
            captureFocusSnapshot = FocusedElementCache.shared.element
            captureFocusPID = FocusedElementCache.shared.focusedPID
        }

        let output = stateMachine.handle(input)

        // Return/Tab during capture resolves to `.fromPicker`, which the
        // state machine marks consumed so the key selects the highlighted
        // row. But a sub-threshold query like `:q` never surfaced the picker
        // (and a no-match query surfaces it empty), so there's no row to
        // select — `insert` will no-op on its `topResult` guard. Consuming
        // anyway swallows the key and the host app needs a second press.
        // Read the model before `apply`, since insertion resets it.
        var consumesKey = output.consumesKey
        if case .insertEmoji(_, .fromPicker, _) = output.action, viewModel.topResult == nil {
            consumesKey = false
        }

        apply(action: output.action)
        // In excluded apps `apply` suppresses the picker / insertion, but
        // returning a true `consumesKey` would still swallow the keystroke
        // (e.g. Return / Esc / arrows during an invisible capture) and break
        // the host app — see Vim in Terminal, where `:q<Enter>` needed two
        // Enters to quit.
        return captureIsExcluded ? false : consumesKey
    }

    /// Exclusion verdict for the active capture. Prefers the flag cached at
    /// `:` time; falls back to re-deriving from `captureContext` so an emoji
    /// action can never slip through if the flag was somehow cleared while the
    /// capture is still live. No AX call — `captureContext` was snapshotted
    /// when capture began, and a real app/focus change cancels the capture
    /// outright, so the snapshot stays authoritative for the capture's life.
    private var captureExcluded: Bool {
        if captureIsExcluded { return true }
        guard let ctx = captureContext else { return false }
        return exclusions.isExcluded(bundleID: ctx.bundleID, url: ctx.url)
    }

    private func apply(action: TriggerAction) {
        switch action {
        case .none:
            break

        case .closePicker:
            viewModel.reset()
            pickerWindow.hide()
            stateMachine.emptyPickerActive = false
            // Backspacing below the picker threshold (or demoting `::` symbols
            // scope) emits .closePicker while the SM stays in .capturing. The
            // capture metadata — exclusion flag, focus snapshot — must survive
            // so typing back up to the threshold still respects the exclusion
            // and focus checks. Only tear it down once the SM has gone idle.
            if case .capturing = stateMachine.state { break }
            captureContext = nil
            captureFocusSnapshot = nil
            captureFocusPID = nil
            captureIsExcluded = false

        case .openPicker(let q, let scope):
            if captureExcluded { break }
            updateResults(query: q, scope: scope)
            if q.isEmpty {
                // `:?` (empty query) → favorites + most-used. Debounced so a
                // follow-up keystroke (`:)`, `:smile`) cancels it before it flashes.
                scheduleEmptyPickerShow()
            } else {
                // Defer one tick: the keystroke moves the caret in the focused
                // app after the tap callback returns. AX returns stale coords if
                // we ask before then.
                scheduleRepositionAndShow()
            }

        case .refreshPicker(let q, let scope):
            if captureExcluded { break }
            updateResults(query: q, scope: scope)
            scheduleRepositionAndShow()

        case .moveSelection(let delta):
            if delta > 0 { viewModel.selectNext() } else { viewModel.selectPrevious() }

        case .insertEmoji(let q, let mode, let scope):
            if captureExcluded { break }
            // `.exactMatch` passed the closing `:` through to the focused
            // app — wait one tick for it to land before deleting `:query:`.
            // `.fromPicker` consumed the key, so we can act immediately.
            switch mode {
            case .exactMatch:
                DispatchQueue.main.async { [weak self] in
                    self?.insert(query: q, mode: .exactMatch, scope: scope)
                }
            case .fromPicker:
                if viewModel.topResult?.emoji.hexcode == EmojiBrowser.sentinelHexcode {
                    // Browse row: grow the panel into the grid instead of
                    // inserting. Delete count covers the typed `:` (+ `::`).
                    let leading = (scope == .symbolsOnly) ? 2 : 1
                    expandToBrowser(deleteCount: q.count + leading)
                } else {
                    insert(query: q, mode: .fromPicker, scope: scope)
                }
            }

        case .checkEmoticon(let q, let term):
            viewModel.reset()
            pickerWindow.hide()
            stateMachine.reset()
            let wasExcluded = captureIsExcluded
            captureContext = nil
            captureFocusSnapshot = nil
            captureFocusPID = nil
            captureIsExcluded = false
            if wasExcluded { break }
            // 80ms gives the passed-through terminator time to land in slow
            // text fields before synth-backspaces fire. One-tick wasn't
            // enough — terminator could end up stranded after the emoji
            // (`:)` → `🙂)`).
            let seqAtDispatch = inputSeq
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self else { return }
                self.handleEmoticon(query: q, terminator: term)
                if self.inputSeq != seqAtDispatch { self.pendingEmoticonUndo = nil }
            }

        case .checkAmbientEmoticon(let word, let term):
            // Ambient emoticons aren't colon-triggered, so the per-capture
            // exclusion flag isn't set here. Check fresh against the active
            // app instead.
            let context = AppContextDetector.current()
            if exclusions.isExcluded(bundleID: context.bundleID, url: context.url) { break }
            let seqAtDispatch = inputSeq
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self else { return }
                self.handleAmbientEmoticon(word: word, terminator: term)
                if self.inputSeq != seqAtDispatch { self.pendingEmoticonUndo = nil }
            }

        case .insertAmbientEmoticon(let word, let trailing):
            let context = AppContextDetector.current()
            if exclusions.isExcluded(bundleID: context.bundleID, url: context.url) { break }
            // No terminator; the last char of `word` was the trigger and
            // was passed through. Same 80ms wait as above.
            let seqAtDispatch = inputSeq
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self else { return }
                // `<3` typed flush before a digit (`<30`) means a number — if
                // that digit was the very next keystroke, skip the conversion
                // entirely so it stays literal. (A digit typed after a longer
                // pause, once ❤️ has rendered, just yields `❤️0` — reverting it
                // in-flight tangles with the async insert, so we don't.)
                if AmbientEmoticonTable.revocableByTrailingDigit(word),
                   self.lastDigitSeq == seqAtDispatch &+ 1 {
                    return
                }
                self.handleAmbientEmoticonImmediate(word: word, trailing: trailing)
                if self.inputSeq != seqAtDispatch { self.pendingEmoticonUndo = nil }
            }

        case .abortEmoticon:
            // User paused too long for this to be a genuine emoticon. Close
            // the picker; leave `:query<term>` in the app as-is.
            viewModel.reset()
            pickerWindow.hide()
            stateMachine.reset()
            captureContext = nil
            captureFocusSnapshot = nil
            captureFocusPID = nil
            captureIsExcluded = false
            pendingEmoticonUndo = nil

        case .maybeUndoEmoticon:
            // Unreachable: Engine intercepts cmdZ before the state machine
            // sees it. Here for switch exhaustiveness.
            _ = performEmoticonUndoIfFresh()

        case .triggerKonami(let deleteCount):
            viewModel.reset()
            pickerWindow.hide()
            captureContext = nil
            captureFocusSnapshot = nil
            captureFocusPID = nil
            captureIsExcluded = false
            // Sequence chars are all consumed today so deleteCount is 0;
            // honor non-zero defensively in case that changes.
            DispatchQueue.main.async {
                if deleteCount > 0 {
                    TextInserter.deleteBackward(deleteCount)
                }
                KonamiPayoff.start()
                EasterEggTracker.record(.k99)
            }

        case .openGifPicker:
            // `:::` stays in the focused app and is deleted later (with the
            // typed query) when the user picks a GIF. Defer to the next
            // runloop tick so the third colon has landed before we anchor
            // the panel to the caret.
            viewModel.reset()
            pickerWindow.hide()
            captureContext = nil
            captureFocusSnapshot = nil
            captureFocusPID = nil
            captureIsExcluded = false
            // Toggle off → `:::` is just three colons in text.
            if !gifSearchEnabled {
                stateMachine.reset()
                break
            }
            // Re-evaluate the focused field. The state-machine `:::` path
            // is tracked across any state, so the secure-field guard at
            // the first-colon site (which only fires in `.idle`) does not
            // cover this case — without this check, keystrokes after
            // `:::` typed in a password field would leak to Giphy.
            let liveGifContext = AppContextDetector.current()
            if liveGifContext.focusedFieldIsSecure {
                stateMachine.reset()
                break
            }
            // Exclusion list applies to GIF search too when the user
            // hasn't opted into the bypass.
            if !gifBypassExclusions,
               exclusions.isExcluded(bundleID: liveGifContext.bundleID, url: liveGifContext.url) {
                stateMachine.reset()
                break
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let anchor = CaretLocator.caretRect()
                PickerContextStore.capture(caretOutcome: CaretLocator.lastOutcome, resolvedCaret: anchor)
                DebugRecorder.record(.gif, "open", ["outcome": CaretLocator.lastOutcome])
                self.gifPickerWindow.show(near: anchor)
            }

        case .refreshGifPicker(let q):
            gifPickerWindow.setQuery(q)

        case .closeGifPicker:
            gifPickerWindow.hide()

        case .pickGif(let deleteCount):
            // `:::query` is sitting in the focused app. The window owns the
            // delete + paste sequence and only fires deletion once the GIF
            // download succeeds, so a network failure doesn't wipe the
            // user's typed text without inserting a replacement.
            //
            // When Enter is the "Load more" affordance, picker stays open
            // and we skip the paste path entirely.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.gifPickerWindow.consumeEnterAsLoadMore() {
                    // Picker stays open — re-arm the state machine so
                    // further typing / arrows / Esc keep routing here
                    // instead of leaking into the focused app.
                    self.stateMachine.resumeGifSearching(query: self.gifPickerWindow.currentQuery)
                    return
                }
                self.gifPickerWindow.pickSelectedAndPaste(deleteCount: deleteCount)
            }

        case .moveGifSelection(let direction):
            gifPickerWindow.move(direction)

        case .refreshBrowser(let q):
            viewModel.browser?.setQuery(q)

        case .moveBrowser(let direction):
            viewModel.browser?.move(direction)

        case .pickBrowser:
            pickFromBrowser()

        case .closeBrowser:
            collapseBrowser()

        case .expandBrowser:
            // ↓/↑ on the pill — the typed `:` (1 char) is erased on pick.
            expandToBrowser(deleteCount: 1)

        case .pickIndex(let index):
            if captureExcluded { break }
            guard index >= 0, index < viewModel.results.count else { break }
            let scored = viewModel.results[index]
            // Never quick-pick the trailing Browse chevron.
            if scored.emoji.hexcode == EmojiBrowser.sentinelHexcode { break }
            viewModel.selectedIndex = index
            insert(query: "", mode: .fromPicker, scope: .normal)

        case .closePickerRestoringQuestion:
            viewModel.reset()
            pickerWindow.hide()
            stateMachine.emptyPickerActive = false
            clearCaptureState()
            // The `?` from `:?` was swallowed; type it back so the focused app
            // shows the literal `:?` after Esc.
            TextInserter.replace(charactersToDelete: 0, with: "?")
        }
    }

    private func scheduleRepositionAndShow() {
        // Defer one tick: the tap callback runs before the OS delivers the
        // keystroke to the focused app, so the caret hasn't moved yet. AX
        // returns stale coordinates if we ask now.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard !self.viewModel.results.isEmpty else {
                self.pickerWindow.hide()
                return
            }
            if self.focusHasChangedSinceCapture() {
                self.cancelCapture()
                return
            }
            let anchor = CaretLocator.caretRect()
            PickerContextStore.capture(caretOutcome: CaretLocator.lastOutcome, resolvedCaret: anchor)
            DebugRecorder.record(.picker, "open", [
                "outcome": CaretLocator.lastOutcome,
                "resultCount": "\(self.viewModel.results.count)",
            ])
            self.pickerWindow.show(near: anchor)
        }
    }

    private func focusHasChangedSinceCapture() -> Bool {
        let cache = FocusedElementCache.shared
        if let snapPID = captureFocusPID,
           let currentPID = cache.focusedPID,
           snapPID != currentPID {
            return true
        }
        guard let snapshot = captureFocusSnapshot else {
            return false
        }
        if let current = cache.element {
            return !CFEqual(snapshot, current)
        }
        // Nil current element = transition; trust the PID check above.
        return false
    }

    /// Show for the Quick Access pill, deferred one tick so the swallowed
    /// trigger char is processed and the caret has settled first. A newer
    /// keystroke advances `inputSeq`, cancelling this before it fires. Only
    /// once it actually shows do we tell the state machine to claim the arrows.
    private func scheduleEmptyPickerShow() {
        let seq = inputSeq
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.inputSeq == seq else { return }
            guard case .capturing(let q) = self.stateMachine.state, q.isEmpty else { return }
            if self.focusHasChangedSinceCapture() {
                self.cancelCapture()
                return
            }
            guard !self.viewModel.results.isEmpty else { return }
            let anchor = CaretLocator.caretRect()
            PickerContextStore.capture(caretOutcome: CaretLocator.lastOutcome, resolvedCaret: anchor)
            DebugRecorder.record(.picker, "openEmpty", ["results": "\(self.viewModel.results.count)"])
            self.pickerWindow.show(near: anchor)
            // Now the picker owns ↑↓ / Return for favorites selection. The
            // emoji-row count (excludes the trailing Browse row) bounds the
            // digit quick-pick so an out-of-range digit starts a search.
            self.stateMachine.pillEmojiCount = max(0, self.viewModel.results.count - 1)
            self.stateMachine.emptyPickerActive = true
        }
    }

    /// Bare-`:` corpus: the 8 Quick Access slots (pinned glyphs + most-used
    /// auto-fill), then a trailing "Browse all emojis…" row.
    private func emptyQueryResults() -> [ScoredEmoji] {
        var rows = QuickAccess
            .resolved(store: quickAccess, database: database, usage: usage)
            .map { ScoredEmoji(emoji: $0, matchedShortcode: $0.primaryShortcode) }
        rows.append(EmojiBrowser.browseRow)
        return rows
    }

    // MARK: - Full-library browser (the picker panel, grown)

    /// Menu-bar / global-hotkey entry. These fire independently of the event
    /// tap, so — unlike the `:` paths — they must explicitly honor pause +
    /// permissions (`isActive` is false then), refuse to act in a secure field,
    /// and clear any GIF picker that's up. If a `:query` capture is in flight,
    /// that text is already in the field and must be erased on pick.
    func showBrowser() {
        guard isActive else { return }
        let context = AppContextDetector.current()
        if context.focusedFieldIsSecure {
            DebugRecorder.record(.engine, "secureFieldBlocked")
            return
        }
        gifPickerWindow.hide()
        let deleteCount: Int
        if case .capturing(let q) = stateMachine.state {
            // Erase the typed `:query` — or `::query` in symbols scope. Mirrors
            // the keyboard Browse-row path in apply(.insertEmoji).
            let leading = stateMachine.captureScope == .symbolsOnly ? 2 : 1
            deleteCount = q.count + leading
        } else {
            deleteCount = 0
        }
        captureContext = context
        captureFocusSnapshot = FocusedElementCache.shared.element
        captureFocusPID = FocusedElementCache.shared.focusedPID
        expandToBrowser(deleteCount: deleteCount)
    }

    /// Grow the picker panel into the full grid and hand the keyboard to the
    /// browser. `deleteCount` is the typed `:` erased when the user picks.
    private func expandToBrowser(deleteCount: Int) {
        browserDeleteCount = deleteCount
        captureIsExcluded = false
        stateMachine.enterBrowsing(query: "")
        viewModel.browser = EmojiBrowserViewModel(database: database, quickAccess: quickAccess)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.viewModel.compact = false
            self.viewModel.expanded = true
            let anchor = CaretLocator.caretRect()
            PickerContextStore.capture(caretOutcome: CaretLocator.lastOutcome, resolvedCaret: anchor)
            DebugRecorder.record(.picker, "browserOpen")
            self.pickerWindow.showExpanded(near: anchor)
        }
    }

    private func pickFromBrowser() {
        let emoji = viewModel.browser?.selectedEmoji
        let delete = browserDeleteCount
        // Copy instead of typing only when there's nowhere to type (e.g. the
        // browser was opened over the Finder). The exclusion list doesn't apply
        // here — the global hotkey is an explicit action, so a pick types into
        // the focused field even in excluded apps.
        let copy = !(captureContext?.focusedFieldIsEditable ?? true)
        collapseBrowser()
        guard let emoji else { return }
        let glyph = emoji.tonedGlyph
        if copy {
            copyToClipboard(glyph)
        } else {
            TextInserter.replace(charactersToDelete: delete, with: glyph)
        }
        recordUsage(emoji: emoji)
        SeasonalGates.fire(for: emoji)
        DebugRecorder.record(.insert, "browserPick", ["del": "\(delete)", "copied": "\(copy)"])
    }

    private func copyToClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        CopyToast.show(string)
        DebugRecorder.record(.insert, "clipboardCopy")
    }

    private func collapseBrowser() {
        stateMachine.reset()
        viewModel.reset()
        pickerWindow.hide()
        clearCaptureState()
    }

    private func updateResults(query: String, scope: CaptureScope) {
        // Empty query → the compact favorites pill; anything typed → the
        // vertical shortcode list.
        viewModel.compact = query.isEmpty
        guard !query.isEmpty else {
            viewModel.update(query: "", results: emptyQueryResults())
            return
        }
        var results = FuzzyMatcher.search(
            query: query,
            in: database,
            usage: usage,
            corpus: corpusFor(scope: scope),
            useFrequencyBoost: useFrequencyBoost
        )
        DebugRecorder.record(.picker, "search", [
            "queryLen": "\(query.count)",
            "results": "\(results.count)",
            "scope": "\(scope)",
        ])
        // Trailing Browse row mirrors the `:?` favorites pill — a no-match query
        // still hides the picker (results stay empty), but any hit list lets
        // the user fall through to the full grid.
        if !results.isEmpty {
            results.append(EmojiBrowser.browseRow)
        }
        viewModel.update(query: query, results: results)
    }

    private func corpusFor(scope: CaptureScope) -> SearchCorpus {
        switch scope {
        case .symbolsOnly:
            return .symbolsOnly
        case .normal:
            if symbolsEnabled && !symbolsRequireDoubleColon {
                return .emojiAndSymbols
            }
            return .emojiOnly
        }
    }

    private func insert(query: String, mode: InsertMode, scope: CaptureScope) {
        defer {
            stateMachine.reset()
            viewModel.reset()
            pickerWindow.hide()
            captureContext = nil
            captureFocusSnapshot = nil
            captureFocusPID = nil
            captureIsExcluded = false
            // Any text-modifying action drops the pending emoticon undo.
            pendingEmoticonUndo = nil
        }

        // `:foo` = 1, `::foo` = 2.
        let leadingColons = (scope == .symbolsOnly) ? 2 : 1

        switch mode {
        case .fromPicker:
            // Closing colon was consumed; `:query` (or `::query`) is in the
            // focused app. User explicitly picked a row, including special
            // rows (🎁 ???, 🎲).
            guard let scored = viewModel.topResult else { return }
            DebugRecorder.record(.insert, "fromPicker", ["scope": "\(scope)"])
            let charsToDelete = query.count + leadingColons
            // The Browse sentinel is intercepted in `apply` before `insert`.
            if triggerEasterEgg(hexcode: scored.emoji.hexcode, deleteCount: charsToDelete) {
                return
            }
            if scored.emoji.hexcode == FuzzyMatcher.k02Hex {
                guard let pick = database.all.randomElement() else { return }
                TextInserter.replace(charactersToDelete: charsToDelete, with: pick.tonedGlyph)
                EasterEggTracker.record(.k02)
                return  // random rolls shouldn't bias future search
            }
            TextInserter.replace(charactersToDelete: charsToDelete, with: scored.emoji.tonedGlyph)
            recordUsage(emoji: scored.emoji)
            SeasonalGates.fire(for: scored.emoji)

        case .exactMatch:
            // Typed text is `:query:` (or `::query:`). Delete only if
            // something resolves; otherwise leave the text alone.
            let key = query.lowercased()
            DebugRecorder.record(.insert, "exactMatch", ["scope": "\(scope)"])
            let charsToDelete = query.count + leadingColons + 1  // + trailing colon

            // `::query:`: top-1 fuzzy against symbols, exact label only.
            // No easter eggs, no random.
            if scope == .symbolsOnly {
                let hits = FuzzyMatcher.search(
                    query: query, in: database, usage: [:],
                    corpus: .symbolsOnly,
                    useFrequencyBoost: false, limit: 5
                )
                if let exact = hits.first(where: { $0.matchedShortcode.lowercased() == key }) {
                    TextInserter.replace(charactersToDelete: charsToDelete, with: exact.emoji.character)
                    bumpSymbolCounter()
                }
                return
            }

            // `EggIndex` keeps trigger words as SHA-256 hashes — plain
            // keywords don't appear in source or the binary. The returned id
            // matches the hexcode constant.
            if let id = EggIndex.id(forExactQuery: key) {
                if id == FuzzyMatcher.k02Hex {
                    guard let pick = database.all.randomElement() else { return }
                    TextInserter.replace(charactersToDelete: charsToDelete, with: pick.character)
                    EasterEggTracker.record(.k02)
                    return
                }
                if triggerEasterEgg(hexcode: id, deleteCount: charsToDelete) {
                    return
                }
            }
            if let exact = database.exact(key) {
                TextInserter.replace(charactersToDelete: charsToDelete, with: exact.tonedGlyph)
                recordUsage(emoji: exact)
                SeasonalGates.fire(for: exact)
                return
            }
        }
    }

    /// Returns true if `hexcode` matched (and the text was already deleted).
    private func triggerEasterEgg(hexcode: String, deleteCount: Int) -> Bool {
        switch hexcode {
        case FuzzyMatcher.k01Hex:
            TextInserter.deleteBackward(deleteCount)
            EmojiRain.start()
            EasterEggTracker.record(.k01)
        case FuzzyMatcher.k03Hex:
            TextInserter.deleteBackward(deleteCount)
            MoofSound.play()
            EasterEggTracker.record(.k03)
        case FuzzyMatcher.k04Hex:
            TextInserter.deleteBackward(deleteCount)
            ConfettiRain.start()
            ConfettiSound.play()
            EasterEggTracker.record(.k04)
        case FuzzyMatcher.k05Hex:
            TextInserter.deleteBackward(deleteCount)
            PrideWave.start()
            EasterEggTracker.record(.k05)
        case FuzzyMatcher.k06Hex:
            TextInserter.deleteBackward(deleteCount)
            SosumiSound.play()
            EasterEggTracker.record(.k06)
        case FuzzyMatcher.k07Hex:
            TextInserter.deleteBackward(deleteCount)
            FloppySound.play()
            EasterEggTracker.record(.k07)
        case FuzzyMatcher.k08Hex:
            TextInserter.deleteBackward(deleteCount)
            DialupSound.play()
            EasterEggTracker.record(.k08)
        case FuzzyMatcher.k09Hex:
            TextInserter.deleteBackward(deleteCount)
            WilhelmScream.play()
            EasterEggTracker.record(.k09)
        case FuzzyMatcher.k10Hex:
            TextInserter.deleteBackward(deleteCount)
            Snowfall.start()
            EasterEggTracker.record(.k10)
        case FuzzyMatcher.k11Hex:
            TextInserter.deleteBackward(deleteCount)
            MatrixRain.start()
            EasterEggTracker.record(.k11)
        case FuzzyMatcher.k12Hex:
            TextInserter.deleteBackward(deleteCount)
            Fireworks.start()
            EasterEggTracker.record(.k12)
        case FuzzyMatcher.k13Hex:
            TextInserter.deleteBackward(deleteCount)
            Trogdor.start()
            EasterEggTracker.record(.k13)
        case FuzzyMatcher.k14Hex:
            TextInserter.deleteBackward(deleteCount)
            HatchClock.start()
            EasterEggTracker.record(.k14)
        case FuzzyMatcher.k15Hex:
            TextInserter.deleteBackward(deleteCount)
            WarpDrive.start()
            EasterEggTracker.record(.k15)
        case FuzzyMatcher.k16Hex:
            TextInserter.deleteBackward(deleteCount)
            FlyingToasters.start()
            EasterEggTracker.record(.k16)
        case FuzzyMatcher.k17Hex:
            TextInserter.deleteBackward(deleteCount)
            BouncingDVD.start()
            EasterEggTracker.record(.k17)
        case FuzzyMatcher.k19Hex:
            TextInserter.deleteBackward(deleteCount)
            BlueScreen.start()
            EasterEggTracker.record(.k19)
        case FuzzyMatcher.k99Hex:
            TextInserter.deleteBackward(deleteCount)
            KonamiPayoff.start()
            EasterEggTracker.record(.k99)
        case FuzzyMatcher.k20Hex:
            TextInserter.deleteBackward(deleteCount)
            // Let synth-backspaces drain before opening the key window;
            // otherwise the game swallows them.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                MainActor.assumeIsolated {
                    SnakeGame.start()
                    EasterEggTracker.record(.k20)
                }
            }
            return true
        case FuzzyMatcher.k21Hex:
            TextInserter.deleteBackward(deleteCount)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                MainActor.assumeIsolated {
                    TicTacToeGame.start()
                    EasterEggTracker.record(.k21)
                }
            }
            return true
        case FuzzyMatcher.k22Hex:
            TextInserter.deleteBackward(deleteCount)
            MyLegSound.play()
            EasterEggTracker.record(.k22)
        case FuzzyMatcher.k23Hex:
            TextInserter.deleteBackward(deleteCount)
            TadaSound.play()
            EasterEggTracker.record(.k23)
        case FuzzyMatcher.k24Hex:
            TextInserter.deleteBackward(deleteCount)
            XPLogin.start()
            EasterEggTracker.record(.k24)
        case FuzzyMatcher.k25Hex:
            TextInserter.deleteBackward(deleteCount)
            SolitaireWin.start()
            EasterEggTracker.record(.k25)
        case FuzzyMatcher.k27Hex:
            TextInserter.deleteBackward(deleteCount)
            EasterEggTracker.record(.k27)
            // Let backspaces land before focus shifts to the browser,
            // else the deletes hit the URL bar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                Rickroll.go()
            }
        case FuzzyMatcher.k29Hex:
            TextInserter.deleteBackward(deleteCount)
            CRTPowerOff.start()
            EasterEggTracker.record(.k29)
        case FuzzyMatcher.k30Hex:
            TextInserter.deleteBackward(deleteCount)
            // Same backspace-drain pattern as Snake — celery man opens
            // a key window that would otherwise swallow them.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                MainActor.assumeIsolated {
                    CeleryMan.start()
                    EasterEggTracker.record(.k30)
                }
            }
            return true
        case FuzzyMatcher.k35Hex:
            TextInserter.deleteBackward(deleteCount)
            TrainGame.start()
            ChooChooSound.play()
            EasterEggTracker.record(.k35)
        case FuzzyMatcher.k49Hex:
            TextInserter.deleteBackward(deleteCount)
            // Let synth-backspaces drain before opening the key window;
            // otherwise the game swallows them.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                MainActor.assumeIsolated {
                    WordleGame.start()
                    EasterEggTracker.record(.k49)
                }
            }
            return true
        case FuzzyMatcher.k50Hex:
            TextInserter.deleteBackward(deleteCount)
            DiskOptimizer.start()
            EasterEggTracker.record(.k50)
            return true
        default:
            return false
        }
        return true
    }

    private func recordUsage(emoji: Emoji) {
        usage[emoji.hexcode, default: 0] += 1
        UserDefaults.standard.set(usage, forKey: PrefsKey.usageCounts)
        // Symbols come from the mixed corpus too (`:foo:` with symbols on
        // and no double-colon required), and pick paths route through here.
        // Branch on the synthetic hexcode prefix so symbols don't pad the
        // emoji milestone count.
        if emoji.hexcode.hasPrefix("SYM_") {
            TelemetryStore.recordSymbol()
            bumpSymbolCounter()
        } else {
            TelemetryStore.recordEmoji(hexcode: emoji.hexcode)
            bumpEmojiCounter()
        }
    }

    /// Seeded from `usageCounts` the first time we touch it so existing
    /// users' next emoji insert fires every milestone they've cleared.
    private func bumpEmojiCounter() {
        let defaults = UserDefaults.standard
        let current = (defaults.object(forKey: PrefsKey.totalEmojiInserted) as? Int) ?? seedEmojiTotal()
        let next = current + 1
        defaults.set(next, forKey: PrefsKey.totalEmojiInserted)
        checkEmojiMilestones(next)
    }

    private func bumpSymbolCounter() {
        let defaults = UserDefaults.standard
        let current = (defaults.object(forKey: PrefsKey.totalSymbolInserted) as? Int) ?? seedSymbolTotal()
        let next = current + 1
        defaults.set(next, forKey: PrefsKey.totalSymbolInserted)
        EasterEggTracker.record(.k42)
    }

    /// Pure diagnostic tally — no milestone eggs ride on it, so no seeding.
    /// Lets the debug report show whether emoticon conversions are landing.
    private func bumpEmoticonCounter() {
        TelemetryStore.recordEmoticon()
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: PrefsKey.totalEmoticonInserted) + 1,
                     forKey: PrefsKey.totalEmoticonInserted)
    }

    private func seedEmojiTotal() -> Int {
        usage.reduce(0) { $1.key.hasPrefix("SYM_") ? $0 : $0 + $1.value }
    }

    private func seedSymbolTotal() -> Int {
        usage.reduce(0) { $1.key.hasPrefix("SYM_") ? $0 + $1.value : $0 }
    }

    /// `record(_:)` is idempotent, so we can check every threshold on every
    /// bump without gating. Backfilled users sweep the whole chain at once
    /// on their next insert.
    private func checkEmojiMilestones(_ total: Int) {
        if total >= 1         { EasterEggTracker.record(.k36) }
        if total >= 100       { EasterEggTracker.record(.k37) }
        if total >= 1_000     { EasterEggTracker.record(.k38) }
        if total >= 10_000    { EasterEggTracker.record(.k39) }
        if total >= 100_000   { EasterEggTracker.record(.k40) }
        if total >= 1_000_000 { EasterEggTracker.record(.k41) }
    }

    private func recordGifInserted() {
        TelemetryStore.recordGif()
        let defaults = UserDefaults.standard
        let current = (defaults.object(forKey: PrefsKey.totalGifInserted) as? Int) ?? 0
        let next = current + 1
        defaults.set(next, forKey: PrefsKey.totalGifInserted)
        if next >= 1         { EasterEggTracker.record(.k43) }
        if next >= 100       { EasterEggTracker.record(.k44) }
        if next >= 1_000     { EasterEggTracker.record(.k45) }
        if next >= 10_000    { EasterEggTracker.record(.k46) }
        if next >= 100_000   { EasterEggTracker.record(.k47) }
        if next >= 1_000_000 { EasterEggTracker.record(.k48) }
    }

    /// Convert `:query<terminator>` into an emoticon, or no-op.
    private func handleEmoticon(query: String, terminator: Character) {
        let enabled = (UserDefaults.standard.object(forKey: PrefsKey.emoticonsEnabled) as? Bool) ?? true
        guard enabled, let match = EmoticonTable.match(query: query, terminator: terminator) else {
            pendingEmoticonUndo = nil
            return
        }
        DebugRecorder.record(.emoticon, "convert", ["consumesTerminator": "\(match.consumesTerminator)"])
        // App reads `:<query><terminator>` — delete all three. Restore the
        // terminator after the emoji unless it was part of the emoticon.
        let charsToDelete = 1 + query.count + 1
        let replacement = match.consumesTerminator
            ? match.emoji
            : match.emoji + String(terminator)
        TextInserter.replace(charactersToDelete: charsToDelete, with: replacement)
        bumpEmoticonCounter()

        let original = ":" + query + String(terminator)
        pendingEmoticonUndo = EmoticonUndo(
            emojiInserted: replacement,
            originalText: original,
            insertedAt: Date(),
            pid: FocusedElementCache.shared.focusedPID
        )
    }

    /// Immediate-fire ambient: the whole word is the emoticon body, no
    /// trailing terminator. Delete `word.count` chars in the focused app
    /// and insert `emoji + trailing`. `trailing` is non-empty only when
    /// the state machine deferred firing a shorter match (`<-`) and the
    /// next char (`x` in `<-x`) failed to extend it to a longer one
    /// (`<->`) — that char was consumed and is re-emitted here so the
    /// final field reads `←x` instead of `<←`.
    private func handleAmbientEmoticonImmediate(word: String, trailing: String) {
        let enabled = (UserDefaults.standard.object(forKey: PrefsKey.emoticonsEnabled) as? Bool) ?? true
        guard enabled,
              Engine.arrowConversionActive() || !AmbientEmoticonTable.isArrow(word),
              let emoji = AmbientEmoticonTable.emoji(for: word) else {
            pendingEmoticonUndo = nil
            return
        }
        DebugRecorder.record(.emoticon, "ambientImmediate")
        let replacement = emoji + trailing
        TextInserter.replace(charactersToDelete: word.count, with: replacement)
        bumpEmoticonCounter()

        pendingEmoticonUndo = EmoticonUndo(
            emojiInserted: replacement,
            originalText: word + trailing,
            insertedAt: Date(),
            pid: FocusedElementCache.shared.focusedPID
        )
    }

    /// Ambient counterpart to `handleEmoticon` — a word with no leading `:`
    /// followed by a terminator, looked up in `AmbientEmoticonTable`.
    private func handleAmbientEmoticon(word: String, terminator: Character) {
        let enabled = (UserDefaults.standard.object(forKey: PrefsKey.emoticonsEnabled) as? Bool) ?? true
        guard enabled,
              Engine.arrowConversionActive() || !AmbientEmoticonTable.isArrow(word),
              let emoji = AmbientEmoticonTable.emoji(for: word) else {
            pendingEmoticonUndo = nil
            return
        }
        DebugRecorder.record(.emoticon, "ambient")
        // Ambient entries are letter/punct sequences with no trailing
        // whitespace, so the terminator always survives the conversion.
        let charsToDelete = word.count + 1
        let replacement = emoji + String(terminator)
        TextInserter.replace(charactersToDelete: charsToDelete, with: replacement)
        bumpEmoticonCounter()

        let original = word + String(terminator)
        pendingEmoticonUndo = EmoticonUndo(
            emojiInserted: replacement,
            originalText: original,
            insertedAt: Date(),
            pid: FocusedElementCache.shared.focusedPID
        )
    }

    /// Returns true if an undo fired (caller should consume the key).
    /// `appending` is tacked onto the restored original in the *same*
    /// replacement — used by the `<30` rescue to fold the triggering digit in
    /// atomically, so the restore can't interleave with a real keystroke.
    @discardableResult
    private func performEmoticonUndoIfFresh(appending suffix: String = "") -> Bool {
        guard let entry = pendingEmoticonUndo else { return false }
        if Date().timeIntervalSince(entry.insertedAt) > Self.emoticonUndoWindow {
            pendingEmoticonUndo = nil
            return false
        }
        if let storedPID = entry.pid,
           let currentPID = FocusedElementCache.shared.focusedPID,
           storedPID != currentPID {
            pendingEmoticonUndo = nil
            return false
        }
        // Grapheme-count, not UTF-16: macOS deletes a ZWJ sequence as one
        // backspace and TextInserter sends one per grapheme.
        let emojiLen = entry.emojiInserted.count
        TextInserter.replace(charactersToDelete: emojiLen, with: entry.originalText + suffix)
        pendingEmoticonUndo = nil
        DebugRecorder.record(.emoticon, "undo")
        return true
    }

}

/// Cmd+Z or Backspace within `Engine.emoticonUndoWindow` reverses this.
private struct EmoticonUndo {
    let emojiInserted: String
    let originalText: String
    let insertedAt: Date
    let pid: pid_t?
}
