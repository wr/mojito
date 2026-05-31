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
    /// Click-to-pick fires this so Engine can reset its trigger state. The
    /// state machine doesn't observe SwiftUI taps, so without this it would
    /// stay in `.gifSearching` and keep mirroring typed chars after the
    /// picker is already gone.
    var onPickClicked: (() -> Void)?
    /// Fired exactly once per GIF successfully copied to the clipboard, so
    /// Engine can bump milestone counters. Independent of the paste step —
    /// firing the achievement on copy means a secure-field bail-out (which
    /// skips the paste) still counts.
    var onGifInserted: (() -> Void)?

    private let panel: NSPanel
    private let viewModel: GifPickerViewModel
    private var clickMonitorLocal: Any?
    private var clickMonitorGlobal: Any?
    private var copyTask: Task<Void, Never>?

    init() {
        self.viewModel = GifPickerViewModel()

        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: GifPickerLayout.width, height: GifPickerLayout.panelHeight),
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
        // Not `.canJoinAllSpaces` — see PickerWindow: it flashes onto the Space
        // you swipe to before the Space-change observer dismisses it.
        panel.collectionBehavior = [.fullScreenAuxiliary, .transient]

        let view = GifPickerView(
            viewModel: viewModel,
            onPick: { [weak self] asset in self?.handleClickPick(asset) },
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
        let size = NSSize(width: GifPickerLayout.width, height: GifPickerLayout.panelHeight)
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
        handlePick(asset, paste: false, deleteCount: 0)
    }

    /// Like `pickSelected()` but synthesizes a ⌘V into the focused app once
    /// the clipboard write completes, so the GIF lands inline rather than
    /// just sitting on the clipboard. `deleteCount` chars are erased from
    /// the focused app first — but only *after* the GIF download succeeds,
    /// so a network failure doesn't silently wipe the user's typed query.
    func pickSelectedAndPaste(deleteCount: Int) {
        guard let asset = viewModel.selectedAsset() else { return }
        handlePick(asset, paste: true, deleteCount: deleteCount)
    }

    /// Returns true when Enter was consumed by the "Load more" affordance
    /// (so Engine knows to skip the delete + paste flow and keep the
    /// picker open). False otherwise — caller proceeds with the normal
    /// pick-and-paste path.
    func consumeEnterAsLoadMore() -> Bool {
        guard viewModel.isLoadMoreFocused else { return false }
        viewModel.loadMore()
        return true
    }

    /// Engine reads this after a load-more Enter so it can re-arm the
    /// state machine with the still-active query — picker stays open.
    var currentQuery: String { viewModel.query }

    /// Click path mirrors the Enter path: delete `:::query` from the
    /// focused app and paste the GIF inline. Engine resets state via
    /// the `onPickClicked` callback.
    private func handleClickPick(_ asset: GifAsset) {
        handlePick(asset, paste: true, deleteCount: viewModel.query.count + 3)
        onPickClicked?()
    }

    private func handlePick(_ asset: GifAsset, paste: Bool, deleteCount: Int) {
        copyTask?.cancel()
        let url = asset.originalURL
        hide()
        copyTask = Task {
            let copied = await GifClipboard.copy(from: url)
            await MainActor.run {
                if copied { onGifInserted?() }
                guard copied, paste else { return }
                // Delete the typed `:::query` only after the GIF actually
                // made it to the clipboard. Earlier deletion would silently
                // wipe the user's text on a network failure.
                if deleteCount > 0 {
                    TextInserter.deleteBackward(deleteCount)
                }
                // The download is async — by the time it completes the user
                // could have switched to a password field or another app.
                // Bail on paste rather than synthesizing ⌘V into the wrong
                // place; the GIF still sits on the clipboard so they can
                // paste manually if they want it.
                if AppContextDetector.current().focusedFieldIsSecure { return }
                TextInserter.pasteFromClipboard()
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
