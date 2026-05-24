import SwiftUI

// MARK: - Welcome

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Type :emoji: anywhere.")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Slack-style shortcodes in any text field, anywhere on your Mac.")
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

/// First-step onboarding animation. Uses a real `NSTextView` for the chat-bubble text
/// and the production `PickerView` for the popup — so the demo is rendered through the
/// same pipeline as the actual product. No fake caret, no replica picker, no baseline
/// math: just programmatic text insertion + the real components reacting to it.
///
/// The state machine still drives timing, but each phase change pokes the NSTextView
/// (via `replaceCharacters`) instead of swapping SwiftUI Text values.
private struct WelcomeAnimation: View {

    fileprivate struct Snippet {
        let prefix: String
        let query: String   // Partial shortcode typed after `:` (e.g. "tad")
        let emoji: String
    }

    private let snippets: [Snippet] = [
        Snippet(prefix: "Just shipped this ",       query: "tad",   emoji: "🎉"),
        Snippet(prefix: "Pull request open ",       query: "eye",   emoji: "👀"),
        Snippet(prefix: "Tests are green ",         query: "check", emoji: "✅"),
        Snippet(prefix: "Side of fries with that ", query: "eggp",  emoji: "🍆"),
    ]

    @State private var snippetIndex: Int = 0
    /// What's currently visible in the text view (excluding the typed `:query`).
    @State private var committedText: String = ""
    /// The `:query` being typed (or empty if not in query phase).
    @State private var queryText: String = ""
    /// Set to a non-nil emoji to trigger the replace-and-hold step.
    @State private var pendingCommit: String? = nil
    /// Single shared view model — reusing it across snippets prevents the cost of
    /// constructing a new `@Published`-backed instance + tearing down/setting up
    /// SwiftUI subscriptions on every snippet cycle. Visibility is controlled by
    /// `pickerVisible` instead of nil-ing this out.
    @StateObject private var pickerViewModel = PickerViewModel()
    @State private var pickerVisible: Bool = false
    @State private var caretRectInBubble: CGRect = .zero
    /// Total snippet cycles run. After `maxCycles` the animation stops so it isn't
    /// burning CPU + accumulating SwiftUI churn forever on the welcome screen.
    @State private var cyclesCompleted: Int = 0
    /// Set to true once the animation has finished its cycles. Tells `BubbleTextView`
    /// to release first-responder status so the OS-native caret stops blinking — a
    /// blinking caret causes WindowServer to recomposite the entire onboarding window
    /// every ~500ms, which is the main steady-state CPU cost while sitting on the
    /// welcome screen.
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
            // Solid bubble + a single shadow reads better than a translucent glass
            // surface — translucent backgrounds sample through the onboarding window
            // and pick up whatever's behind it (desktop, other apps).
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
        // Bail if we've already run through the snippets enough times. The final
        // state (committed emoji + bubble) stays on screen.
        if cyclesCompleted >= maxCycles {
            return
        }

        // Snap to initial state without animation.
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

        // First filter letter: show the (already-existing) picker view model.
        pickerVisible = true
        let queryChars = Array(snippet.query)
        for i in 1...queryChars.count {
            let q = String(queryChars.prefix(i))
            queryText = ":" + q
            updatePicker(pickerViewModel, query: q)
            try? await Task.sleep(for: .milliseconds(Int.random(in: 50...95)))
        }

        try? await Task.sleep(for: .milliseconds(220))

        // Commit: replace `:query` with the emoji. Picker disappears.
        pendingCommit = snippet.emoji
        queryText = ""
        committedText = snippet.prefix + snippet.emoji
        pickerVisible = false

        try? await Task.sleep(for: .milliseconds(1100))

        // Advance, or stop if this was the last snippet of the last cycle.
        let nextIndex = (snippetIndex + 1) % snippets.count
        if nextIndex == 0 {
            cyclesCompleted += 1
        }
        if cyclesCompleted >= maxCycles {
            // Drop first responder so the caret stops blinking; final state stays.
            animationStopped = true
            return
        }
        snippetIndex = nextIndex
    }

    private func updatePicker(_ vm: PickerViewModel, query: String) {
        // Look the results up via the shared cache so we don't re-score 3500 emoji
        // on every keystroke during the demo. The cache lives outside SwiftUI state
        // so reads/writes don't trigger view re-renders.
        let results = WelcomeFuzzyCache.shared.results(for: query)
        vm.update(query: query, results: results)
    }
}

/// Singleton cache for the onboarding demo's fuzzy results. Keeping this out of
/// SwiftUI's `@State` is important: writing to a `@State` cache forces a view re-
/// render on every keystroke, which compounds with the typing-driven re-renders
/// and balloons memory.
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

/// Wraps an `NSTextView` so we can drive the bubble's content programmatically while
/// getting real native rendering — caret blink, font metrics, baseline alignment, and
/// emoji presentation are all the OS's responsibility, not ours. We also read back the
/// caret rect on every update so the SwiftUI picker overlay can anchor to it.
private struct BubbleTextView: NSViewRepresentable {
    let committedText: String
    let queryText: String
    let commitEmoji: String?
    @Binding var caretRect: CGRect
    /// When false, the text view resigns first-responder so the OS-native blinking
    /// caret stops, taking WindowServer compositing load with it.
    let showCaret: Bool

    final class Coordinator {
        var lastRenderedText: String = ""
        var lastShowCaret: Bool = true
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> Container {
        // Editable + first-responder so the OS draws and blinks the native caret;
        // `NoTypingTextView` eats key events so user input can't disrupt the demo.
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

        // Solid (non-translucent) bubble — translucent backgrounds bleed through the
        // window and pick up whatever's behind it. SwiftUI applies the shadow.
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

        // Make the text view first responder so the native caret blinks. Retry on the
        // next runloop tick because the window may not be set yet on first call.
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

        // First-responder gate. Releasing first responder when the animation is done
        // is what actually drops WindowServer CPU back to ~zero — without it, the
        // OS-native caret keeps blinking, invalidating the bubble region every blink.
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

        // If the text hasn't changed, skip the rest. SwiftUI re-renders BubbleTextView
        // on every parent state change (including changes to caretRect, which we write
        // back from this method); without this guard, each re-render queues another
        // caret-rect query and SwiftUI accumulates layout caches.
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

        // Caret to end of text.
        let endIndex = (full as NSString).length
        textView.setSelectedRange(NSRange(location: endIndex, length: 0))

        if showCaret, container.window?.firstResponder !== textView {
            container.window?.makeFirstResponder(textView)
        }

        // Force layout so `firstRect(forCharacterRange:)` returns the post-update
        // position synchronously, without needing a runloop tick.
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        let caretRange = NSRange(location: endIndex, length: 0)
        let rectInTextView = textView.firstRect(forCharacterRange: caretRange, actualRange: nil)
        guard let window = textView.window else { return }
        let rectInWindow = window.convertFromScreen(rectInTextView)
        let rectInContainer = container.convert(rectInWindow, from: nil)
        // Sub-pixel deltas from font metrics / layout rounding would otherwise
        // re-enter updateNSView every animation tick, each time queuing another
        // async SwiftUI state write. Only react to changes the eye can see.
        let dx = abs(rectInContainer.minX - caretRect.minX)
        let dy = abs(rectInContainer.minY - caretRect.minY)
        if rectInContainer.maxY.isFinite, (dx > 0.5 || dy > 0.5) {
            // Dispatch to next tick so we're not mutating SwiftUI state during view
            // evaluation. (Synchronous write would trigger a "Modifying state during
            // view update" warning.)
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
        // Flip so the container's coordinate system matches SwiftUI's (origin
        // top-left). Without this, `convert(_, from: nil)` yields y values measured
        // from the bottom — feeding those into SwiftUI's `.offset(y:)` puts the
        // picker far below where the caret actually is.
        override var isFlipped: Bool { true }
    }
}

/// NSTextView that's editable (so the OS draws the blinking caret when first responder)
/// but silently drops every key event — the user can't actually disrupt the demo by
/// typing into it. The system caret is the entire reason we keep `isEditable = true`.
private final class NoTypingTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        // Swallow.
    }
    override func keyUp(with event: NSEvent) {
        // Swallow.
    }
    override func insertText(_ string: Any, replacementRange: NSRange) {
        // Programmatic edits via textStorage still work; user-driven inserts don't.
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        false
    }
    /// Force the caret to always be drawn while we're the first responder, even when
    /// no text has changed recently. The default blink behavior already kicks in for
    /// editable first-responder text views; this is a belt-and-suspenders override.
    override var shouldDrawInsertionPoint: Bool { true }
}

/// Solid, non-translucent picker chrome for the onboarding demo. The production
/// picker uses Liquid Glass (`.menu` blending `.behindWindow`), but that material
/// samples through the onboarding window and reads as wrong when there's nothing
/// meaningful behind it. A solid surface + shadow is closer to what the user
/// actually wants the demo to convey.
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

    /// Each system prompt only opens its OS-level "Open Settings / Deny" alert the FIRST
    /// time it's invoked per app launch. After that, subsequent calls are silent. To
    /// avoid the awkward stuck-alert experience (the alert lingering after the user
    /// has already granted in System Settings), we fire each prompt at most once: the
    /// first click of "Allow" triggers the OS alert; subsequent clicks open Settings
    /// directly so the user can toggle by hand.
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
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("\(AppInfo.displayName) needs permission to work with your keyboard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            VStack(spacing: 10) {
                permissionRow(
                    title: "Accessibility",
                    detail: "Lets Mojito anchor the picker next to your text cursor.",
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
                    detail: "Lets Mojito watch keystrokes for `:` triggers. Nothing is logged.",
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

            Button("Privacy details…") { showPrivacyDetails = true }
                .buttonStyle(.link)

            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showPrivacyDetails) {
            PrivacyDetailsSheet()
        }
    }

    private func permissionRow(title: String, detail: String, granted: Bool, onAllow: @escaping () -> Void) -> some View {
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

// MARK: - Done

struct DoneStep: View {
    @AppStorage(PrefsKey.launchAtLogin) private var launchAtLogin: Bool = false
    @AppStorage(PrefsKey.skinTone) private var skinToneRaw: String = SkinTone.default.rawValue
    @State private var autoUpdates: Bool = UpdaterCoordinator.shared.automaticUpdates

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                VStack(spacing: 6) {
                    Text("You're all set 🍋‍🟩")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("\(AppInfo.displayName) lives in your menu bar. Try typing `:tada:` in any text field.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
            }
            .padding(.top, 4)

            Form {
                HStack {
                    Text("Skin tone")
                    Spacer(minLength: 12)
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
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(maxWidth: 460)
        }
    }
}

