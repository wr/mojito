import SwiftUI

// MARK: - Welcome

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Autocomplete `:emoji:` everywhere.")
                    .font(.system(size: 28, weight: .semibold))
                Text("Type `:` to search for any emoji or symbol in seconds.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            .padding(.top, 4)

            WelcomeAnimation()
                .frame(height: 280)
                .padding(.top, 8)

            Spacer(minLength: 0)
        }
    }
}

/// Real `NSTextView` + the production `PickerView` so the demo renders
/// through the same pipeline as the real app. State changes poke the
/// NSTextView programmatically.
private struct WelcomeAnimation: View {

    fileprivate struct Snippet {
        let prefix: String
        let query: String  // partial after `:` (e.g. "tad")
        let emoji: String
    }

    // Pulled from the homepage carousel (mojito-site/picker.js `scenes`).
    private let snippets: [Snippet] = [
        Snippet(prefix: "Hit deadline ",           query: "fire",   emoji: "🔥"),
        Snippet(prefix: "see you soon ",           query: "wave",   emoji: "👋"),
        Snippet(prefix: "fix the ",                query: "bug",    emoji: "🐛"),
        Snippet(prefix: "Just shipped a new app ", query: "rocket", emoji: "🚀"),
        Snippet(prefix: "Pick up ",                query: "gift",   emoji: "🎁"),
    ]

    @State private var snippetIndex: Int = 0
    /// Visible text excluding the typed `:query`.
    @State private var committedText: String = ""
    @State private var queryText: String = ""
    /// Non-nil triggers the replace-and-hold step.
    @State private var pendingCommit: String? = nil
    /// Shared across snippets — building a new `@Published`-backed VM and
    /// SwiftUI subscriptions per cycle would be expensive.
    @StateObject private var pickerViewModel = PickerViewModel()
    @State private var pickerVisible: Bool = false
    @State private var caretRectInBubble: CGRect = .zero
    @State private var cyclesCompleted: Int = 0
    /// True once cycles are done. Drops the text view's first-responder
    /// status so the OS caret stops blinking — every blink invalidates
    /// the bubble region and is the main steady-state CPU cost.
    @State private var animationStopped: Bool = false
    private let maxCycles: Int = 2

    var body: some View {
        ZStack(alignment: .topLeading) {
            BubbleTextView(
                committedText: committedText,
                queryText: queryText,
                commitEmoji: pendingCommit,
                caretRect: $caretRectInBubble,
                showCaret: !animationStopped
            )
            .frame(width: 460, height: 88)
            // Solid bubble — translucent would sample whatever's behind
            // the onboarding window (desktop, other apps).
            .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 4)

            if pickerVisible && !pickerViewModel.results.isEmpty {
                PickerView(viewModel: pickerViewModel)
                    .modifier(OnboardingPickerChrome())
                    .frame(width: 280)
                    .offset(
                        x: max(8, min(caretRectInBubble.minX - 4, 460 - 280 - 8)),
                        y: caretRectInBubble.maxY + 6
                    )
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 460, height: 240, alignment: .topLeading)
        .animation(.easeOut(duration: 0.10), value: pickerVisible)
        .task(id: snippetIndex) { await runAnimation() }
    }

    // MARK: - Animation loop

    private var snippet: Snippet { snippets[snippetIndex] }

    @MainActor
    private func runAnimation() async {
        // Final state stays on screen after maxCycles.
        if cyclesCompleted >= maxCycles {
            return
        }

        committedText = ""
        queryText = ""
        pendingCommit = nil
        pickerVisible = false
        pickerViewModel.update(query: "", results: [])

        try? await Task.sleep(for: .milliseconds(180))

        let prefixChars = Array(snippet.prefix)
        for i in 1...prefixChars.count {
            committedText = String(prefixChars.prefix(i))
            let last = prefixChars[i - 1]
            let base = Int.random(in: 22...55)
            let wordBreakBonus = (last == " ") ? Int.random(in: 12...32) : 0
            try? await Task.sleep(for: .milliseconds(base + wordBreakBonus))
        }

        try? await Task.sleep(for: .milliseconds(80))

        queryText = ":"
        try? await Task.sleep(for: .milliseconds(100))

        pickerVisible = true
        let queryChars = Array(snippet.query)
        for i in 1...queryChars.count {
            let q = String(queryChars.prefix(i))
            queryText = ":" + q
            updatePicker(pickerViewModel, query: q)
            try? await Task.sleep(for: .milliseconds(Int.random(in: 50...95)))
        }

        try? await Task.sleep(for: .milliseconds(220))

        pendingCommit = snippet.emoji
        queryText = ""
        committedText = snippet.prefix + snippet.emoji
        pickerVisible = false

        try? await Task.sleep(for: .milliseconds(1100))

        let nextIndex = (snippetIndex + 1) % snippets.count
        if nextIndex == 0 {
            cyclesCompleted += 1
        }
        if cyclesCompleted >= maxCycles {
            animationStopped = true
            return
        }
        snippetIndex = nextIndex
    }

    private func updatePicker(_ vm: PickerViewModel, query: String) {
        // Cache outside SwiftUI state so reads/writes don't trigger re-renders.
        let results = WelcomeFuzzyCache.shared.results(for: query)
        vm.update(query: query, results: results)
    }
}

@MainActor
private final class WelcomeFuzzyCache {
    static let shared = WelcomeFuzzyCache()
    private var cache: [String: [ScoredEmoji]] = [:]

    func results(for query: String) -> [ScoredEmoji] {
        if let hit = cache[query] { return hit }
        let r = FuzzyMatcher.search(
            query: query,
            in: EmojiDatabase.shared,
            usage: [:],
            corpus: .emojiOnly,
            useFrequencyBoost: false,
            limit: 5
        )
        cache[query] = r
        return r
    }
}

/// `NSTextView` so caret blink, font metrics, and emoji presentation are
/// the OS's job. Caret rect is read back on every update so the SwiftUI
/// picker overlay can anchor to it.
private struct BubbleTextView: NSViewRepresentable {
    let committedText: String
    let queryText: String
    let commitEmoji: String?
    @Binding var caretRect: CGRect
    /// False = resign first responder so the OS caret stops blinking.
    let showCaret: Bool

    final class Coordinator {
        var lastRenderedText: String = ""
        var lastShowCaret: Bool = true
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> Container {
        // Editable + first-responder for the native caret blink;
        // `NoTypingTextView` eats key events so users can't disrupt the demo.
        let textView = NoTypingTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.font = .systemFont(ofSize: 17)
        textView.textColor = .labelColor
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isRichText = false
        textView.allowsUndo = false

        let container = Container(textView: textView)
        container.translatesAutoresizingMaskIntoConstraints = false

        // Solid — translucent would bleed through the window.
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        container.layer?.cornerRadius = 14
        container.layer?.cornerCurve = .continuous
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        container.layer?.borderWidth = 0.5
        container.layer?.masksToBounds = true

        textView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textView.topAnchor.constraint(equalTo: container.topAnchor),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Deferred because the window may not be set on first call.
        DispatchQueue.main.async {
            container.window?.makeFirstResponder(textView)
        }
        return container
    }

    func updateNSView(_ container: Container, context: Context) {
        let textView = container.textView
        let combined = committedText + queryText
        let full = commitEmoji != nil ? committedText : combined
        let coord = context.coordinator

        // Releasing first responder is what drops WindowServer CPU back
        // to ~zero — the caret blink invalidates the bubble region every tick.
        if coord.lastShowCaret != showCaret {
            coord.lastShowCaret = showCaret
            if showCaret {
                container.window?.makeFirstResponder(textView)
            } else {
                if container.window?.firstResponder === textView {
                    container.window?.makeFirstResponder(nil)
                }
            }
        }

        // Without this guard, every parent re-render (incl. our own
        // caretRect writeback) queues another rect query and balloons
        // layout caches.
        if coord.lastRenderedText == full {
            return
        }
        coord.lastRenderedText = full

        if textView.string != full {
            textView.string = full
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 17),
                .foregroundColor: NSColor.labelColor,
            ]
            textView.textStorage?.setAttributes(attrs, range: NSRange(location: 0, length: (full as NSString).length))
        }

        let endIndex = (full as NSString).length
        textView.setSelectedRange(NSRange(location: endIndex, length: 0))

        if showCaret, container.window?.firstResponder !== textView {
            container.window?.makeFirstResponder(textView)
        }

        // Force layout so `firstRect(forCharacterRange:)` returns the
        // post-update position synchronously.
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        let caretRange = NSRange(location: endIndex, length: 0)
        let rectInTextView = textView.firstRect(forCharacterRange: caretRange, actualRange: nil)
        guard let window = textView.window else { return }
        let rectInWindow = window.convertFromScreen(rectInTextView)
        let rectInContainer = container.convert(rectInWindow, from: nil)
        // Sub-pixel rounding would re-enter every tick. Only react to
        // changes the eye can see.
        let dx = abs(rectInContainer.minX - caretRect.minX)
        let dy = abs(rectInContainer.minY - caretRect.minY)
        if rectInContainer.maxY.isFinite, (dx > 0.5 || dy > 0.5) {
            // Defer so we're not mutating state during view evaluation.
            DispatchQueue.main.async {
                caretRect = rectInContainer
            }
        }
    }

    final class Container: NSView {
        let textView: NSTextView
        init(textView: NSTextView) {
            self.textView = textView
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        // Match SwiftUI's top-left origin so `convert(_, from: nil)` y
        // values feed into `.offset(y:)` correctly.
        override var isFlipped: Bool { true }
    }
}

/// `isEditable = true` so the OS draws the native caret; key events are
/// swallowed so the user can't disrupt the demo. textStorage edits still work.
private final class NoTypingTextView: NSTextView {
    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
    override func insertText(_ string: Any, replacementRange: NSRange) {}
    override func performKeyEquivalent(with event: NSEvent) -> Bool { false }
    override var shouldDrawInsertionPoint: Bool { true }
}

/// Solid chrome — the production Liquid Glass picker samples through the
/// onboarding window and reads as wrong with nothing meaningful behind it.
private struct OnboardingPickerChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: Color.black.opacity(0.14), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Permissions (combined)

struct PermissionsStep: View {
    let accessibilityGranted: Bool
    let inputMonitoringGranted: Bool
    let promptAccessibility: () -> Void
    let promptInputMonitoring: () -> Void
    let openAccessibilitySettings: () -> Void
    let openInputMonitoringSettings: () -> Void

    /// Each system prompt only shows its OS alert the first time per
    /// launch. Subsequent "Allow" clicks open Settings directly so the
    /// user isn't stuck staring at a silent alert.
    @State private var axPromptFired: Bool = false
    @State private var imPromptFired: Bool = false
    @State private var showPrivacyDetails: Bool = false

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "accessibility")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Grant accessibility permissions")
                    .font(.system(size: 22, weight: .semibold))
                Text("\(AppInfo.displayName) needs permission to work with your keyboard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            VStack(spacing: 10) {
                permissionRow(
                    title: "Accessibility",
                    detail: "Lets \(AppInfo.displayName) anchor the picker next to your text cursor.",
                    granted: accessibilityGranted,
                    onAllow: {
                        if axPromptFired {
                            openAccessibilitySettings()
                        } else {
                            promptAccessibility()
                            axPromptFired = true
                        }
                    }
                )
                permissionRow(
                    title: "Input Monitoring",
                    detail: "Lets \(AppInfo.displayName) watch keystrokes for `:` triggers. Nothing is logged.",
                    granted: inputMonitoringGranted,
                    onAllow: {
                        if imPromptFired {
                            openInputMonitoringSettings()
                        } else {
                            promptInputMonitoring()
                            imPromptFired = true
                        }
                    }
                )
            }
            .frame(maxWidth: 480)

            VStack(spacing: 6) {
                Button("Privacy details…") { showPrivacyDetails = true }
                    .buttonStyle(.link)

                // A fresh grant sometimes only registers on a clean launch.
                if !(accessibilityGranted && inputMonitoringGranted) {
                    HStack(spacing: 4) {
                        Text("Already allowed but still not detected?")
                            .foregroundStyle(.secondary)
                        Button("Quit & Reopen") { AppRelauncher.relaunch() }
                            .buttonStyle(.link)
                    }
                    .font(.system(size: 13))
                }
            }

            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showPrivacyDetails) {
            PrivacyDetailsSheet()
        }
    }

    private func permissionRow(title: LocalizedStringKey, detail: LocalizedStringKey, granted: Bool, onAllow: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)
            } else {
                Button("Allow", action: onAllow)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Features

/// Enable/disable the emoji, symbols, and GIF features and pick each one's
/// trigger — the same controls as Settings ▸ General, reusing
/// `SettingsSectionHeader` + `TriggerPicker`. Edits persist immediately.
struct FeaturesStep: View {
    @State private var triggers: TriggerConfig = TriggerConfigStore.load()

    /// Opens claimed by the other active triggers, so each menu grays collisions.
    private func takenOpens(excluding mode: TriggerMode) -> Set<String> {
        var normalized = triggers
        normalized.normalize()
        return Set(normalized.active.filter { $0.mode != mode }.map(\.open))
    }

    var body: some View {
        Form {
            Section {
                SettingsSectionHeader(
                    systemImage: "face.smiling.fill",
                    tint: .orange,
                    title: "Emoji",
                    subtitle: "Type a shortcut to insert any emoji.",
                    iconSize: 16,
                    iconOffsetY: -1,
                    isOn: $triggers.emoji.enabled
                )
                if triggers.emoji.enabled {
                    TriggerPicker(
                        mode: .emoji,
                        open: $triggers.emoji.open,
                        takenOpens: takenOpens(excluding: .emoji),
                        defaultOpen: TriggerConfig.default.emoji.open
                    )
                }
            }

            Section {
                SettingsSectionHeader(
                    systemImage: "command",
                    tint: .indigo,
                    title: "Symbols",
                    subtitle: "Symbols like ★ ✓ ÷ ©.",
                    isOn: $triggers.symbols.enabled
                )
                if triggers.symbols.enabled {
                    TriggerPicker(
                        mode: .symbols,
                        open: $triggers.symbols.open,
                        takenOpens: takenOpens(excluding: .symbols),
                        defaultOpen: TriggerConfig.default.symbols.open,
                        sameAsEmoji: $triggers.symbolsFollowEmoji,
                        defaultFollowsEmoji: true
                    )
                }
            }

            Section {
                SettingsSectionHeader(
                    systemImage: "photo.fill",
                    tint: .pink,
                    title: "GIF search",
                    subtitle: "GIFs from Giphy.",
                    isOn: $triggers.gif.enabled
                )
                if triggers.gif.enabled {
                    TriggerPicker(
                        mode: .gif,
                        open: $triggers.gif.open,
                        takenOpens: takenOpens(excluding: .gif),
                        defaultOpen: TriggerConfig.default.gif.open
                    )
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .frame(maxWidth: 480)
        .onChange(of: triggers) { _, _ in
            TriggerConfigStore.save(triggers)
        }
    }
}

// MARK: - Done

struct DoneStep: View {
    @AppStorage(PrefsKey.skinTone) private var skinToneRaw: String = SkinTone.default.rawValue
    @AppStorage(PrefsKey.replaceSystemEmojiPickerEnabled) private var replacePicker: Bool = false
    @AppStorage(PrefsKey.launchAtLogin) private var launchAtLogin: Bool = false
    @State private var autoUpdates: Bool = UpdaterCoordinator.shared.automaticUpdates
    @State private var replaceNeedsLogout = false
    @State private var tryItText = ""
    @FocusState private var tryItFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                VStack(spacing: 6) {
                    Text("You're all set")
                        .font(.system(size: 24, weight: .semibold))
                    Text("\(AppInfo.displayName) lives in your menu bar — give it a try:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }

                TextField("Try typing :smile", text: $tryItText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
                    .frame(maxWidth: 280)
                    .focused($tryItFocused)
            }
            .padding(.top, 4)

            Form {
                Section {
                    HStack {
                        Text("Skin tone")
                        Spacer(minLength: 12)
                        skinToneSwatches
                    }

                    Toggle(isOn: $replacePicker) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Replace system emoji picker")
                            Text("Open \(AppInfo.displayName) on ⌃⌘Space and the \(Image(systemName: "globe")) key.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if replacePicker && replaceNeedsLogout {
                                Text("Log out and back in to finish handing over the \(Image(systemName: "globe")) key.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .onChange(of: replacePicker) { _, on in
                        if on {
                            SystemEmojiPickerReplacer.shared.replaceSystemPicker()
                            replaceNeedsLogout = SystemEmojiPickerReplacer.shared.needsLogoutForGlobe
                        } else {
                            SystemEmojiPickerReplacer.shared.restoreSystemPicker()
                            replaceNeedsLogout = false
                        }
                    }
                }

                Section {
                    Toggle("Automatic updates", isOn: $autoUpdates)
                        .toggleStyle(.switch)
                        .onChange(of: autoUpdates) { _, newValue in
                            UpdaterCoordinator.shared.automaticUpdates = newValue
                        }

                    Toggle("Start at login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, newValue in
                            LaunchAtLogin.apply(newValue)
                        }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(maxWidth: 460)
        }
        .onAppear {
            // Bring the engine live so the "try it out" field actually expands
            // shortcuts — it isn't started until onboarding finishes otherwise.
            NotificationCenter.default.post(name: .mojitoShouldStartEngine, object: nil)
            // Focus the field once the step's transition has settled.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { tryItFocused = true }
        }
    }

    private var skinToneSwatches: some View {
        HStack(spacing: 4) {
            ForEach(SkinTone.allCases) { tone in
                Button {
                    skinToneRaw = tone.rawValue
                } label: {
                    Text(tone.swatchEmoji)
                        .font(.system(size: 18))
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(skinToneRaw == tone.rawValue
                                      ? Color.accentColor.opacity(0.22)
                                      : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    skinToneRaw == tone.rawValue ? Color.accentColor : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(tone.displayName)
            }
        }
    }
}

