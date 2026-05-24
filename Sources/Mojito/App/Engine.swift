import AppKit
import Combine
import Foundation
import os.log

/// Wires KeyMonitor → state machine → picker → inserter.
@MainActor
final class Engine: ObservableObject, KeyMonitorDelegate {
    @Published private(set) var isActive: Bool = false
    @Published var pausedUntil: Date?

    private let database: EmojiDatabase
    private let exclusions: ExclusionStore
    private let viewModel = PickerViewModel()
    private let pickerWindow: PickerWindow
    private let monitor = KeyMonitor()

    private var stateMachine = TriggerStateMachine()
    private var permissions: PermissionsCoordinator?
    private var permissionsObserver: AnyCancellable?

    /// Bundle ID of app where current capture started — if it changes, we cancel.
    private var captureContext: ActiveContext?
    /// AX-focused element snapshot taken when `:` was typed. The picker is
    /// shown one runloop tick later; if focus has moved (e.g. user hit ⌘Space
    /// for Spotlight between the `:` and the picker show), we abort instead
    /// of plopping the picker on the wrong window. Identity comparison via
    /// `CFEqual` is intentional — we want the *same* AX element, not just a
    /// similar one.
    private var captureFocusSnapshot: AXUIElement?
    /// PID of the focused-app process at capture start. Used as a fallback
    /// when the AX element identity can't be compared (e.g. AX returned nil
    /// for the new focus and we can't tell if it's the same element).
    private var captureFocusPID: pid_t?
    private var usage: [String: Int]
    private var workspaceObserver: NSObjectProtocol?
    private var prefsObserver: NSObjectProtocol?
    /// Cached prefs read in `FuzzyMatcher.search` on every keystroke. Refreshed
    /// on UserDefaults.didChangeNotification instead — measurable per-keystroke
    /// hit when read directly.
    private var useFrequencyBoost: Bool
    private var symbolsEnabled: Bool
    private var symbolsRequireDoubleColon: Bool

    /// Single most-recent emoticon insertion that's still inside its undo
    /// window. Cleared on: successful undo, timeout, focus change, any
    /// non-undo keystroke that would mutate text, app/process changes, or
    /// shutdown. Backs WEL-52 / WEL-53.
    private var pendingEmoticonUndo: EmoticonUndo?
    /// Max seconds after an emoticon insertion during which Cmd+Z or
    /// Backspace will roll it back. After this window the entry is dropped
    /// and the keystroke behaves normally.
    private static let emoticonUndoWindow: TimeInterval = 3.0

    init(database: EmojiDatabase, exclusions: ExclusionStore) {
        self.database = database
        self.exclusions = exclusions
        self.pickerWindow = PickerWindow(viewModel: viewModel)
        self.usage = (UserDefaults.standard.dictionary(forKey: PrefsKey.usageCounts) as? [String: Int]) ?? [:]
        self.useFrequencyBoost = (UserDefaults.standard.object(forKey: PrefsKey.useFrequencyBoost) as? Bool) ?? true
        self.symbolsEnabled = (UserDefaults.standard.object(forKey: PrefsKey.symbolsEnabled) as? Bool) ?? false
        self.symbolsRequireDoubleColon = (UserDefaults.standard.object(forKey: PrefsKey.symbolsRequireDoubleColon) as? Bool) ?? false
        self.stateMachine.symbolsDoubleColonEnabled = self.symbolsEnabled && self.symbolsRequireDoubleColon

        // Mouse-click outside the picker dismisses (same effect as Esc, but doesn't consume).
        pickerWindow.onClickAway = { [weak self] in
            self?.cancelCapture()
        }

        // Cancel capture when the user actually switches apps. Done via NSWorkspace
        // notification instead of polling on every keystroke — the per-keystroke check was
        // racing the picker's `orderFrontRegardless()` and resetting state mid-typing.
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            MainActor.assumeIsolated {
                self?.handleAppActivated(notification: notif)
            }
        }

        // Cancel capture when the focused AX element changes mid-capture (e.g.
        // user types `:`, then ⌘Space → Spotlight before/while the picker is
        // about to render). NSWorkspace.didActivateApplicationNotification
        // alone isn't enough because some focus changes (Spotlight, system
        // panels, in-app field-to-field jumps) don't fire it reliably or fire
        // it too late. The AX-level notification fires synchronously when the
        // focused element changes.
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
                self.stateMachine.symbolsDoubleColonEnabled = self.symbolsEnabled && self.symbolsRequireDoubleColon
            }
        }
    }

    deinit {
        if let obs = workspaceObserver {
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
        // App switch invalidates any pending emoticon-undo entry — the
        // target text field is no longer focused.
        pendingEmoticonUndo = nil
        guard case .capturing = stateMachine.state else { return }
        guard bundleID != captureContext?.bundleID else { return }
        cancelCapture()
    }

    /// AX-level focus-change callback. Distinct from `handleAppActivated`
    /// because some focus shifts (Spotlight, system panels, in-app jumps)
    /// don't fire `didActivateApplicationNotification`.
    private func handleFocusChanged() {
        // Any focus shift drops the pending emoticon-undo entry. The user
        // moving the caret elsewhere means we'd be editing the wrong text.
        pendingEmoticonUndo = nil
        guard case .capturing = stateMachine.state else { return }
        // If we never captured a snapshot (shouldn't happen — we always set
        // both at capture start), be conservative and cancel.
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
        // Same app — check the element identity. CFEqual handles AX element
        // equality correctly across copies.
        if let current = cache.element {
            if !CFEqual(snapshot, current) {
                cancelCapture()
            }
        }
        // If the cache has no element right now, this is a transient nil
        // during a focus transition — wait for the next callback to decide.
    }

    /// Single point that tears down an in-flight capture (picker hidden,
    /// state machine reset, snapshot cleared). Use this instead of
    /// open-coding the three lines so all cancel paths stay in sync.
    private func cancelCapture() {
        stateMachine.reset()
        viewModel.reset()
        pickerWindow.hide()
        captureContext = nil
        captureFocusSnapshot = nil
        captureFocusPID = nil
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
        reconcile()
    }

    func resume() {
        pausedUntil = nil
        UserDefaults.standard.removeObject(forKey: PrefsKey.pausedUntil)
        reconcile()
    }

    /// Clears in-memory and on-disk usage in lockstep — otherwise the next
    /// emoji insert would write the stale in-memory map back to UserDefaults.
    /// Writes an empty dict (rather than `removeObject`) so the dev build's
    /// registered fallback from the release app's domain (see main.swift)
    /// can't shine through and resurrect cleared counts.
    func clearUsageStats() {
        objectWillChange.send()
        usage = [:]
        UserDefaults.standard.set([String: Int](), forKey: PrefsKey.usageCounts)
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
            // The tap may have been disabled because the user revoked Input Monitoring.
            // Let the permissions coordinator know so it resumes polling and we can
            // surface the missing-permission state in the UI.
            self.permissions?.handleInputMonitoringLost()
        }
    }

    private func process(input: TriggerInput) -> Bool {
        // BSOD-style "press any key to continue" effects pre-empt
        // everything — any keystroke pops them off the stack and is
        // consumed so it doesn't leak into the focused app underneath.
        if case .idle = stateMachine.state, EffectDismisser.topWantsAnyKey() {
            EffectDismisser.dismissTop()
            return true
        }

        // Esc bails out of any in-flight full-screen effect first. We only
        // pre-empt when state is idle so an Esc-during-capture still cancels
        // the picker the normal way.
        if case .escape = input, case .idle = stateMachine.state,
           EffectDismisser.dismissTop() {
            return true
        }

        // WEL-53: backspace right after an emoticon insertion undoes it.
        // Only fires when we're idle (so capture-mid backspace still works
        // normally) and there's a fresh undo entry. Any other backspace
        // falls through to the state machine.
        if case .idle = stateMachine.state, case .backspace = input,
           pendingEmoticonUndo != nil, performEmoticonUndoIfFresh() {
            return true
        }
        // WEL-52: Cmd+Z right after an emoticon insertion undoes it.
        // Intercepted here (not in the state machine) because the consume
        // decision depends on whether there's a fresh undo entry — info the
        // state machine doesn't have. If there's no entry, fall through and
        // let cmdZ pass through to the focused app's normal undo.
        if case .cmdZ = input {
            if case .idle = stateMachine.state,
               pendingEmoticonUndo != nil, performEmoticonUndoIfFresh() {
                return true
            }
            return false
        }

        // Before opening, check if current app/site is excluded or if the focused
        // field is a password field. Both must short-circuit BEFORE we transition
        // out of `.idle` — otherwise the state machine starts buffering name chars
        // and the picker renders password fragments in the empty-state row.
        if case .idle = stateMachine.state, case .colon = input {
            let context = AppContextDetector.current()
            if context.focusedFieldIsSecure {
                return false
            }
            if exclusions.isExcluded(bundleID: context.bundleID, url: context.url) {
                return false
            }
            captureContext = context
            // Snapshot the focused element + PID so the deferred picker show
            // (one runloop tick later) and any subsequent focus-change
            // notifications can detect if focus has moved out from under us.
            captureFocusSnapshot = FocusedElementCache.shared.element
            captureFocusPID = FocusedElementCache.shared.focusedPID
        }

        let output = stateMachine.handle(input)
        apply(action: output.action)
        return output.consumesKey
    }

    private func apply(action: TriggerAction) {
        switch action {
        case .none:
            break

        case .closePicker:
            viewModel.reset()
            pickerWindow.hide()
            captureContext = nil
            captureFocusSnapshot = nil
            captureFocusPID = nil

        case .openPicker(let q, let scope):
            updateResults(query: q, scope: scope)
            // Defer one runloop tick so the keystroke has been delivered to the focused app
            // (which moves the caret) before we ask AX where the caret is.
            scheduleRepositionAndShow()

        case .refreshPicker(let q, let scope):
            updateResults(query: q, scope: scope)
            scheduleRepositionAndShow()

        case .moveSelection(let delta):
            if delta > 0 { viewModel.selectNext() } else { viewModel.selectPrevious() }

        case .insertEmoji(let q, let mode, let scope):
            // `.exactMatch` (closing `:`) passes the closing colon through to
            // the focused app — we have to wait one runloop tick for it to
            // arrive before deleting `:query:`. `.fromPicker` (Return / Tab)
            // consumed the key, so we can act immediately.
            switch mode {
            case .exactMatch:
                DispatchQueue.main.async { [weak self] in
                    self?.insert(query: q, mode: .exactMatch, scope: scope)
                }
            case .fromPicker:
                insert(query: q, mode: .fromPicker, scope: scope)
            }

        case .checkEmoticon(let q, let term):
            viewModel.reset()
            pickerWindow.hide()
            stateMachine.reset()
            captureContext = nil
            captureFocusSnapshot = nil
            captureFocusPID = nil
            // Defer ~80ms so the cancel char (which was passed through but
            // not yet processed when this callback fires) actually lands
            // in the focused app's text field before we issue the
            // backspaces. The previous one-runloop-tick delay was racy —
            // on slower fields the synth-backspaces could fire while the
            // terminator was still in flight, leaving it stranded after
            // the inserted emoji (e.g. `:)` → `🙂)`).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.handleEmoticon(query: q, terminator: term)
            }

        case .abortEmoticon:
            // WEL-54: the user paused too long mid-capture for this to be a
            // genuine emoticon attempt. Close the picker; leave the typed
            // `:query<term>` in the focused app as-is. Drop any stale undo
            // entry so a subsequent backspace behaves normally.
            viewModel.reset()
            pickerWindow.hide()
            stateMachine.reset()
            captureContext = nil
            captureFocusSnapshot = nil
            captureFocusPID = nil
            pendingEmoticonUndo = nil

        case .maybeUndoEmoticon:
            // Unreachable in practice — Engine intercepts cmdZ before the
            // state machine sees it. Kept for switch exhaustiveness.
            _ = performEmoticonUndoIfFresh()

        case .triggerKonami(let deleteCount):
            viewModel.reset()
            pickerWindow.hide()
            captureContext = nil
            captureFocusSnapshot = nil
            captureFocusPID = nil
            // Every char in the sequence was consumed, so deleteCount is
            // normally 0. Still honor a non-zero value defensively in case
            // the state machine starts requiring deletion again later.
            DispatchQueue.main.async {
                if deleteCount > 0 {
                    TextInserter.deleteBackward(deleteCount)
                }
                KonamiPayoff.start()
                EasterEggTracker.record(.k99)
            }
        }
    }

    private func scheduleRepositionAndShow() {
        // Run on next tick: the user's keystroke that triggered this action hasn't been
        // delivered to the focused app yet (CGEventTap callback runs *before* delivery), so
        // the caret hasn't moved. Asking AX now returns stale coordinates.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard !self.viewModel.results.isEmpty else {
                self.pickerWindow.hide()
                return
            }
            // Focus may have changed between the `:` trigger and now (e.g.
            // user hit ⌘Space and Spotlight grabbed focus). Don't pop the
            // picker on the wrong window — cancel cleanly instead.
            if self.focusHasChangedSinceCapture() {
                self.cancelCapture()
                return
            }
            let anchor = CaretLocator.caretRect()
            self.pickerWindow.show(near: anchor)
        }
    }

    /// True if the currently-focused AX element (or its owning app's PID)
    /// differs from the snapshot taken at capture start. Conservative: returns
    /// true on PID mismatch even if AX element comparison can't be performed.
    private func focusHasChangedSinceCapture() -> Bool {
        let cache = FocusedElementCache.shared
        if let snapPID = captureFocusPID,
           let currentPID = cache.focusedPID,
           snapPID != currentPID {
            return true
        }
        guard let snapshot = captureFocusSnapshot else {
            // No snapshot recorded — be permissive (this path shouldn't
            // happen in practice since we always set the snapshot at `:`).
            return false
        }
        if let current = cache.element {
            return !CFEqual(snapshot, current)
        }
        // Current element is nil during a transition; trust PID check above.
        return false
    }

    private func updateResults(query: String, scope: CaptureScope) {
        guard !query.isEmpty else {
            viewModel.update(query: "", results: [])
            return
        }
        let results = FuzzyMatcher.search(
            query: query,
            in: database,
            usage: usage,
            corpus: corpusFor(scope: scope),
            useFrequencyBoost: useFrequencyBoost
        )
        viewModel.update(query: query, results: results)
    }

    /// Maps prefs + state-machine scope into the FuzzyMatcher corpus to search.
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
            // Any text-modifying action invalidates the pending emoticon undo —
            // a backspace after a regular emoji insert should not roll back
            // the previous emoticon.
            pendingEmoticonUndo = nil
        }

        // Leading-colon count: `:foo` is 1, `::foo` is 2. Used to compute
        // how many chars to delete before insertion.
        let leadingColons = (scope == .symbolsOnly) ? 2 : 1

        // Two paths:
        //  - `.fromPicker` (Return / Tab): user explicitly selected a row,
        //    so we honor that selection — including special rows (🎁 ???, 🎲).
        //    The closing colon was consumed; only `:query` (or `::query`) is
        //    in the focused app — delete `leadingColons + query.count`.
        //  - `.exactMatch` (closing `:`): the typed text is `:query:` (or
        //    `::query:`). Delete `leadingColons + query.count + 1` iff
        //    something resolves; otherwise leave the text alone.
        switch mode {
        case .fromPicker:
            guard let scored = viewModel.topResult else { return }
            let charsToDelete = query.count + leadingColons
            if triggerEasterEgg(hexcode: scored.emoji.hexcode, deleteCount: charsToDelete) {
                return
            }
            if scored.emoji.hexcode == FuzzyMatcher.k02Hex {
                guard let pick = database.all.randomElement() else { return }
                TextInserter.replace(charactersToDelete: charsToDelete, with: characterWithSkinTone(pick))
                return  // intentionally don't recordUsage — random rolls shouldn't bias future search
            }
            TextInserter.replace(charactersToDelete: charsToDelete, with: characterWithSkinTone(scored.emoji))
            recordUsage(emoji: scored.emoji)

        case .exactMatch:
            let key = query.lowercased()
            let charsToDelete = query.count + leadingColons + 1  // includes trailing colon

            // Symbols-only (`::query:`): top-1 fuzzy search against the symbols
            // corpus, accept only an exact label match. No easter eggs, no random.
            if scope == .symbolsOnly {
                let hits = FuzzyMatcher.search(
                    query: query, in: database, usage: [:],
                    corpus: .symbolsOnly,
                    useFrequencyBoost: false, limit: 5
                )
                if let exact = hits.first(where: { $0.matchedShortcode.lowercased() == key }) {
                    TextInserter.replace(charactersToDelete: charsToDelete, with: exact.emoji.character)
                }
                return
            }

            // Keyword → opaque-id lookup. `EggIndex` keeps the trigger
            // words exclusively as SHA-256 hashes — plain keywords don't
            // appear in source or in the binary. The id it returns is the
            // same string that's already used as the hexcode constant.
            if let id = EggIndex.id(forExactQuery: key) {
                if id == FuzzyMatcher.k02Hex {
                    guard let pick = database.all.randomElement() else { return }
                    TextInserter.replace(charactersToDelete: charsToDelete, with: pick.character)
                    return
                }
                if triggerEasterEgg(hexcode: id, deleteCount: charsToDelete) {
                    return
                }
            }
            if let exact = database.exact(key) {
                TextInserter.replace(charactersToDelete: charsToDelete, with: characterWithSkinTone(exact))
                recordUsage(emoji: exact)
                return
            }
            // No exact match → no replacement. `:query:` stays in the text.
        }
    }

    /// Dispatches every easter-egg sentinel. Returns true if `hexcode` matched
    /// (and the focused-app text was already deleted), false otherwise.
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
            // Wait for the synthetic backspaces above to drain into the
            // focused app — otherwise the new key window swallows them
            // (Snake closes on Esc; the game's keyDown sees nothing else
            // notable, but the focus race is still brittle).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                MainActor.assumeIsolated {
                    SnakeGame.start()
                    EasterEggTracker.record(.k20)
                }
            }
            return true
        case FuzzyMatcher.k21Hex:
            TextInserter.deleteBackward(deleteCount)
            // Same backspace-drain delay as Snake.
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
            // Defer the browser open so the synthetic backspaces above
            // land in the user's text field before focus shifts to the
            // browser. Otherwise the deletes hit the browser's URL bar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                Rickroll.go()
            }
        case FuzzyMatcher.k29Hex:
            TextInserter.deleteBackward(deleteCount)
            CRTPowerOff.start()
            EasterEggTracker.record(.k29)
        case FuzzyMatcher.k30Hex:
            TextInserter.deleteBackward(deleteCount)
            // Wait for the synthetic backspaces above to drain into the
            // focused app — celery man opens a key window (same pattern
            // as SnakeGame/TicTacToeGame) that would otherwise swallow
            // them. The 0.18s delay matches what those games use.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                MainActor.assumeIsolated {
                    CeleryMan.start()
                    EasterEggTracker.record(.k30)
                }
            }
            return true
        default:
            return false
        }
        return true
    }

    private func recordUsage(emoji: Emoji) {
        usage[emoji.hexcode, default: 0] += 1
        UserDefaults.standard.set(usage, forKey: PrefsKey.usageCounts)
    }

    /// Try to convert `:query<terminator>` into an emoticon. No-op if the
    /// emoticons feature is disabled or no entry matches.
    private func handleEmoticon(query: String, terminator: Character) {
        let enabled = (UserDefaults.standard.object(forKey: PrefsKey.emoticonsEnabled) as? Bool) ?? true
        guard enabled, let match = EmoticonTable.match(query: query, terminator: terminator) else {
            // Not an emoticon match — the typed `:query<term>` stays as-is.
            // No undo entry to register; clear any stale one.
            pendingEmoticonUndo = nil
            return
        }
        // The focused app now reads `:<query><terminator>`. Always delete
        // all three; restore the terminator after the emoji if it wasn't
        // part of the emoticon itself.
        let charsToDelete = 1 + query.count + 1
        let replacement = match.consumesTerminator
            ? match.emoji
            : match.emoji + String(terminator)
        TextInserter.replace(charactersToDelete: charsToDelete, with: replacement)

        // Record undo state. The original text that was on screen before the
        // replacement was `:<query><terminator>` — restoring that is what
        // Cmd+Z / Backspace will do during the undo window.
        let original = ":" + query + String(terminator)
        pendingEmoticonUndo = EmoticonUndo(
            emojiInserted: replacement,
            originalText: original,
            insertedAt: Date(),
            pid: FocusedElementCache.shared.focusedPID
        )
    }

    /// Roll back the most recent emoticon conversion if it's still inside
    /// the undo window and the user hasn't moved focus elsewhere. Returns
    /// true if an undo actually fired (caller should consume the key).
    private func performEmoticonUndoIfFresh() -> Bool {
        guard let entry = pendingEmoticonUndo else { return false }
        // Window expired → drop it and let the keystroke through.
        if Date().timeIntervalSince(entry.insertedAt) > Self.emoticonUndoWindow {
            pendingEmoticonUndo = nil
            return false
        }
        // Focus moved to a different app → can't safely surgery the wrong
        // text field. Drop the entry; pass the keystroke through.
        if let storedPID = entry.pid,
           let currentPID = FocusedElementCache.shared.focusedPID,
           storedPID != currentPID {
            pendingEmoticonUndo = nil
            return false
        }
        // Delete the inserted emoji (count grapheme clusters, not UTF-16
        // code units — TextInserter's backspaces are one-per-grapheme since
        // macOS treats the whole ZWJ sequence as one delete). Then type
        // the original `:query<term>` back.
        let emojiLen = entry.emojiInserted.count
        TextInserter.replace(charactersToDelete: emojiLen, with: entry.originalText)
        pendingEmoticonUndo = nil
        return true
    }

    /// Apply the user's skin-tone preference to `emoji` if (a) the emoji
    /// supports tone modifiers and (b) the preference isn't `.default`.
    /// Returns the modified character string (just the base for non-toned
    /// emoji, or default tone).
    private func characterWithSkinTone(_ emoji: Emoji) -> String {
        let tone = SkinTone.current
        guard emoji.supportsSkinTone else { return emoji.character }
        return tone.apply(to: emoji.character)
    }
}

/// Snapshot of a just-completed emoticon insertion that can be reversed by
/// pressing Cmd+Z or Backspace within `Engine.emoticonUndoWindow` seconds.
private struct EmoticonUndo {
    let emojiInserted: String
    let originalText: String
    let insertedAt: Date
    let pid: pid_t?
}
