import AppKit
import SwiftUI

/// Floating panel hosting the GIF search UI. Activating (unlike the emoji
/// `PickerWindow`) so the search field takes first responder + keyboard
/// input goes through SwiftUI directly. Engine pauses keystroke handling
/// while this panel is key.
@MainActor
final class GifPickerWindow {
    /// Engine resets the trigger state machine + dismisses the panel.
    var onClickAway: (() -> Void)?

    private let panel: NSPanel
    private let viewModel: GifPickerViewModel
    private var clickMonitorLocal: Any?
    private var clickMonitorGlobal: Any?
    private var copyTask: Task<Void, Never>?

    init() {
        self.viewModel = GifPickerViewModel()

        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: GifPickerLayout.width, height: 420),
            // Non-activating + becomesKeyOnlyIfNeeded = false lets the
            // panel take keyboard focus for the search field without
            // stealing app activation from whatever was front before.
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let view = GifPickerView(
            viewModel: viewModel,
            onPick: { [weak self] asset in self?.handlePick(asset) },
            onDismiss: { [weak self] in self?.onClickAway?() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = Self.makeChrome(hosting: hosting)
    }

    private static func makeChrome(hosting: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = GifPickerLayout.cornerRadius
            glass.contentView = hosting
            glass.translatesAutoresizingMaskIntoConstraints = false
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = GifPickerLayout.cornerRadius
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }

    /// Whether the panel is currently visible — Engine uses this to know
    /// when to route keystrokes here via the state machine.
    var isVisible: Bool { viewModel.isVisible }

    func show(near caret: CGRect?) {
        let anchor = caret ?? mouseAnchor()
        let size = NSSize(width: GifPickerLayout.width, height: 420)
        let frame = positionedFrame(anchor: anchor, size: size)

        viewModel.reset()
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        viewModel.isVisible = true
        installClickMonitors()
    }

    func hide() {
        copyTask?.cancel()
        copyTask = nil
        panel.orderOut(nil)
        viewModel.isVisible = false
        viewModel.reset()
        removeClickMonitors()
    }

    /// Engine pipes the state machine's GIF query updates in here.
    func setQuery(_ query: String) {
        viewModel.query = query
    }

    func move(_ direction: GifMoveDirection) {
        switch direction {
        case .left:  viewModel.moveSelection(.left)
        case .right: viewModel.moveSelection(.right)
        case .up:    viewModel.moveSelection(.up)
        case .down:  viewModel.moveSelection(.down)
        }
    }

    /// Copies the currently-selected GIF and dismisses. No-op if the
    /// search hasn't returned anything yet.
    func pickSelected() {
        guard let asset = viewModel.selectedAsset() else { return }
        handlePick(asset)
    }

    private func handlePick(_ asset: GifAsset) {
        copyTask?.cancel()
        let url = asset.originalURL
        copyTask = Task { [weak self] in
            _ = await GifClipboard.copy(from: url)
            await MainActor.run {
                self?.hide()
            }
        }
    }

    private func installClickMonitors() {
        guard clickMonitorLocal == nil else { return }
        let types: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        clickMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: types) { [weak self] event in
            if let self, event.window !== self.panel {
                self.onClickAway?()
            }
            return event
        }
        clickMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: types) { [weak self] _ in
            self?.onClickAway?()
        }
    }

    private func removeClickMonitors() {
        if let m = clickMonitorLocal { NSEvent.removeMonitor(m) }
        if let m = clickMonitorGlobal { NSEvent.removeMonitor(m) }
        clickMonitorLocal = nil
        clickMonitorGlobal = nil
    }

    private func positionedFrame(anchor: CGRect, size: CGSize) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) }
                  ?? NSScreen.main
                  ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        let gap: CGFloat = 6

        var origin = CGPoint(x: anchor.minX, y: anchor.minY - size.height - gap)
        if origin.y < visible.minY {
            origin.y = anchor.maxY + gap
        }
        if origin.y + size.height > visible.maxY {
            origin.y = visible.maxY - size.height - gap
        }
        if origin.x + size.width > visible.maxX {
            origin.x = visible.maxX - size.width - 8
        }
        if origin.x < visible.minX {
            origin.x = visible.minX + 8
        }
        return CGRect(origin: origin, size: size)
    }

    private func mouseAnchor() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x, y: mouse.y, width: 1, height: 16)
    }
}
