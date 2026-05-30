import AppKit
import SwiftUI

@MainActor
final class PickerWindow {
    /// Engine resets the state machine and hides the picker.
    var onClickAway: (() -> Void)?

    private let panel: NSPanel
    private let hostingView: NSHostingView<PickerView>
    private let viewModel: PickerViewModel
    private let chrome: NSView
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
        // System menu shadow matches NSMenu's drop shadow exactly.
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        // Tahoe's NSGlassEffectView matches NSMenu / NSPopover's Liquid
        // Glass; pre-26 falls back to NSVisualEffectView `.menu`.
        self.chrome = Self.makeChrome(hosting: hostingView)
        panel.contentView = chrome
    }

    /// Vertical list uses the menu corner radius; the compact pill is a
    /// capsule (radius = half its height).
    private func setCornerRadius(_ radius: CGFloat) {
        if #available(macOS 26.0, *), let glass = chrome as? NSGlassEffectView {
            glass.cornerRadius = radius
        } else {
            chrome.layer?.cornerRadius = radius
        }
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

    /// Anchors near the caret rect, or the mouse if nil.
    func show(near caret: CGRect?) {
        let anchor = caret ?? mouseAnchor()
        // Follow the live system appearance. A borderless panel created once
        // and reused otherwise stays pinned to its launch-time appearance, so
        // the picker looked stuck in light mode after a dark-mode switch.
        panel.appearance = NSApp.effectiveAppearance
        let size = preferredSize()
        setCornerRadius(viewModel.compact ? size.height / 2 : PickerLayout.cornerRadius)
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
            // Ignore clicks on the picker panel; dismiss otherwise.
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
        if viewModel.compact {
            let count = max(viewModel.results.count, 1)
            // Each cell + inter-cell spacing + side padding. The Browse cell
            // also carries a thin leading divider (~3pt) — pad for it.
            let cells = CGFloat(count) * PickerLayout.compactCell
            let gaps = CGFloat(max(count - 1, 0)) * PickerLayout.compactSpacing
            let width = cells + gaps + PickerLayout.compactPadding * 2 + 4
            return CGSize(width: width, height: PickerLayout.compactHeight)
        }
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

        // Prefer below; flip above if no room downward.
        var origin = CGPoint(
            x: anchor.minX,
            y: belowOriginY >= visible.minY ? belowOriginY : aboveOriginY
        )

        if origin.y + size.height > visible.maxY {
            origin.y = visible.maxY - size.height - gap
        }
        if origin.y < visible.minY {
            origin.y = visible.minY + gap
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

enum PickerLayout {
    static let width: CGFloat = 280
    static let rowHeight: CGFloat = 30
    static let footerHeight: CGFloat = 26
    static let maxVisibleRows: Int = 6
    static let cornerRadius: CGFloat = 10

    // Compact horizontal bar (bare-`:` favorites), styled like the macOS
    // predictive emoji strip: a capsule of cells, selected one filled.
    static let compactCell: CGFloat = 34
    static let compactSpacing: CGFloat = 2
    static let compactPadding: CGFloat = 5
    static var compactHeight: CGFloat { compactCell + compactPadding * 2 }
}
