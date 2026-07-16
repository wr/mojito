import AppKit
import SwiftUI
import KeyboardShortcuts

/// A shortcut recorder that captures via the responder chain (`keyDown`) rather
/// than a text field + `NSEvent` local monitor. The library's `Recorder`
/// misbehaves in this app — keys leak into the search field's field editor and
/// valid chords never register — so this purpose-built control sidesteps both.
/// Reads/writes through `KeyboardShortcuts`, so the global hotkey still registers.
///
/// Click to record (the box clears to "Record Shortcut"); press a chord to set
/// it; Escape or clicking away keeps the previous value; Delete clears it.
struct ShortcutRecorder: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil

    func makeNSView(context: Context) -> ShortcutRecorderView {
        ShortcutRecorderView(name: name, onChange: onChange)
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.onChange = onChange
        view.refresh()
    }

    // Hand SwiftUI the exact size so it never stretches the view to fill the
    // available width (which pushed it past the table edge).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ShortcutRecorderView, context: Context) -> CGSize? {
        ShortcutRecorderView.size
    }
}

@MainActor
final class ShortcutRecorderView: NSView {
    let name: KeyboardShortcuts.Name
    var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    private var recording = false { didSet { needsDisplay = true } }
    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton()
    /// Installed only while recording, to dismiss when the user clicks elsewhere.
    private var clickMonitor: Any?
    /// Ends recording when our window stops being key (see `observeKeyLoss`).
    private var keyLossObserver: (any NSObjectProtocol)?

    static let size = NSSize(width: 124, height: 24)

    init(name: KeyboardShortcuts.Name, onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?) {
        self.name = name
        self.onChange = onChange
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        focusRingType = .default
        // Never let the content stretch or shrink this view away from its size.
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        label.alignment = .center
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.lineBreakMode = .byTruncatingTail
        // Truncate rather than forcing the box wider to fit the text.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                    accessibilityDescription: String(localized: "Clear shortcut"))?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearTapped)
        clearButton.refusesFirstResponder = true
        clearButton.isHidden = true
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16),
            // Full width and centered; the clear button overlays the right edge
            // (it's only shown alongside a short chord, never the placeholder).
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeKeyLoss()
        // Removed from the hierarchy (e.g. switched settings tabs) mid-record.
        if window == nil {
            recording = false
            removeClickMonitor()
        }
    }

    override var intrinsicContentSize: NSSize { Self.size }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    private var cornerRadius: CGFloat { 6 }

    override func draw(_ dirtyRect: NSRect) {
        // Native text-field look: white field background, hairline border. The
        // active (recording) state is conveyed by AppKit's focus ring below.
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.textBackgroundColor.setFill()
        path.fill()
        path.lineWidth = 1
        NSColor.separatorColor.setStroke()
        path.stroke()
    }

    // Native focus ring while recording (the box is first responder).
    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }

    /// The whole box is a single click target (the label subview must not eat
    /// clicks) — except the visible clear button. Reuse the default hit logic so
    /// the coordinate math is correct, then redirect label hits to self.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if !clearButton.isHidden, hit == clearButton { return clearButton }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        // Only ever start recording on a click — never toggle off, or a click
        // that AppKit already used to focus the box would immediately cancel it
        // (the "needs a double-click" bug). Escape / click-away dismiss instead.
        if !recording {
            window?.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        recording = true
        label.stringValue = String(localized: "Record Shortcut")
        label.textColor = .secondaryLabelColor
        clearButton.isHidden = true
        installClickMonitor()
        return true
    }

    @objc private func clearTapped() {
        KeyboardShortcuts.setShortcut(nil, for: name)
        onChange?(nil)
        refresh()
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        removeClickMonitor()
        refresh()
        return true
    }

    /// A click anywhere outside the box ends recording (and still reaches its
    /// target, so clicking a button both dismisses and activates it).
    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.recording else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            if !self.bounds.contains(point) {
                self.window?.makeFirstResponder(nil)
            }
            return event
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    /// A recording box is its window's first responder, and that status outlives
    /// the window losing key (clicking another app, or the emoji browser panel
    /// stealing key). Keystrokes stop arriving, but the box stays "recording" —
    /// focus ring showing — while the global event tap resumes the moment
    /// Settings isn't key (see `SettingsWindowController`). The two then fight
    /// over the keyboard: keys get swallowed or leak elsewhere, and because
    /// `mouseDown` no-ops while `recording`, clicking the box won't recover it.
    /// End recording as soon as our window resigns key so the state can't stick.
    private func observeKeyLoss() {
        if let keyLossObserver {
            NotificationCenter.default.removeObserver(keyLossObserver)
            self.keyLossObserver = nil
        }
        guard let window else { return }
        keyLossObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.recording else { return }
                self.window?.makeFirstResponder(nil)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }

        switch event.keyCode {
        case 53: // Escape — cancel, keep previous.
            window?.makeFirstResponder(nil)
            return
        case 51, 117: // Backspace / forward-delete — clear.
            KeyboardShortcuts.setShortcut(nil, for: name)
            onChange?(nil)
            window?.makeFirstResponder(nil)
            return
        default:
            break
        }

        // Require a command/control/option modifier so a bare letter can't
        // become a shortcut. (Shift alone doesn't count.)
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        guard !mods.isEmpty, let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
            NSSound.beep()
            return
        }
        KeyboardShortcuts.setShortcut(shortcut, for: name)
        onChange?(shortcut)
        window?.makeFirstResponder(nil)
    }

    /// Sync the displayed value to the stored shortcut (e.g. after the Replace /
    /// reset buttons set it). No-op while recording so it keeps the prompt.
    func refresh() {
        guard !recording else { return }
        if let shortcut = KeyboardShortcuts.getShortcut(for: name) {
            label.textColor = .labelColor
            label.stringValue = "\(shortcut)"
            clearButton.isHidden = false
        } else {
            label.textColor = .secondaryLabelColor
            label.stringValue = String(localized: "Record Shortcut")
            clearButton.isHidden = true
        }
    }
}
