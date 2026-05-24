import AppKit
import SwiftUI

@MainActor
final class PickerWindow {
    /// Fired when the user clicks anywhere outside the picker panel (inside or outside our
    /// app). Engine resets the state machine + hides the picker in response.
    var onClickAway: (() -> Void)?

    private let panel: NSPanel
    private let hostingView: NSHostingView<PickerView>
    private let viewModel: PickerViewModel
    private var clickMonitorLocal: Any?
    private var clickMonitorGlobal: Any?

    init(viewModel: PickerViewModel) {
        self.viewModel = viewModel
        self.hostingView = NSHostingView(rootView: PickerView(viewModel: viewModel))
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: PickerLayout.width, height: 100),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Let AppKit draw the system menu shadow — matches NSMenu drop shadow exactly.
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        // On Tahoe (macOS 26+) the public Liquid Glass primitive is `NSGlassEffectView` —
        // this is what NSMenu / NSPopover render through internally. On older OSes fall
        // back to NSVisualEffectView with `.menu` material so we still get the right blur.
        panel.contentView = Self.makeChrome(hosting: hostingView)
    }

    private static func makeChrome(hosting: NSHostingView<PickerView>) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = PickerLayout.cornerRadius
            glass.contentView = hosting
            glass.translatesAutoresizingMaskIntoConstraints = false
            return glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .menu
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = PickerLayout.cornerRadius
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
    }

    /// Show the picker, anchoring near the supplied caret rect (or mouse if nil).
    func show(near caret: CGRect?) {
        let anchor = caret ?? mouseAnchor()
        let size = preferredSize()
        let frame = positionedFrame(anchor: anchor, size: size)

        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        viewModel.isVisible = true
        installClickMonitors()
    }

    func reposition(near caret: CGRect?) {
        guard viewModel.isVisible else { return }
        show(near: caret)
    }

    func hide() {
        panel.orderOut(nil)
        viewModel.isVisible = false
        removeClickMonitors()
    }

    // MARK: - Click-away

    private func installClickMonitors() {
        guard clickMonitorLocal == nil else { return }
        let types: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        clickMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: types) { [weak self] event in
            // Ignore clicks that land on the picker panel itself; dismiss for any other window.
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

    // MARK: - Layout

    private func preferredSize() -> CGSize {
        let rowHeight: CGFloat = PickerLayout.rowHeight
        let footerHeight: CGFloat = PickerLayout.footerHeight
        let verticalPadding: CGFloat = 6
        let count = max(min(viewModel.results.count, PickerLayout.maxVisibleRows), 1)
        let height = (CGFloat(count) * rowHeight) + footerHeight + verticalPadding
        return CGSize(width: PickerLayout.width, height: height)
    }

    private func positionedFrame(anchor: CGRect, size: CGSize) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame

        let gap: CGFloat = 6
        let belowOriginY = anchor.minY - size.height - gap
        let aboveOriginY = anchor.maxY + gap

        // Prefer below caret. Flip above if there isn't enough room downward.
        var origin = CGPoint(
            x: anchor.minX,
            y: belowOriginY >= visible.minY ? belowOriginY : aboveOriginY
        )

        // If even the flipped position would clip off the top, clamp down so we stay visible.
        if origin.y + size.height > visible.maxY {
            origin.y = visible.maxY - size.height - gap
        }
        if origin.y < visible.minY {
            origin.y = visible.minY + gap
        }

        // Clip horizontally inside the visible frame.
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

enum PickerLayout {
    static let width: CGFloat = 280
    static let rowHeight: CGFloat = 30
    static let footerHeight: CGFloat = 26
    static let maxVisibleRows: Int = 6
    static let cornerRadius: CGFloat = 10
}
