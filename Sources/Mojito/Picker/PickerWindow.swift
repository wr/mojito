import AppKit
import QuartzCore
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
    /// Separate panel for the pill's number-hotkey tooltip — the pill panel
    /// is too short to host a label above its cells without clipping.
    private var tooltipPanel: NSPanel?
    private var pillTooltipWork: DispatchWorkItem?

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

        viewModel.onPillHover = { [weak self] index in
            self?.handlePillHover(index)
        }
    }

    // MARK: - Pill number-hotkey tooltip

    private func handlePillHover(_ index: Int?) {
        pillTooltipWork?.cancel()
        guard let index, index < 8, index < viewModel.results.count else {
            hidePillTooltip()
            return
        }
        let scored = viewModel.results[index]
        guard scored.emoji.hexcode != EmojiBrowser.sentinelHexcode else {
            hidePillTooltip()
            return
        }
        let name = ":\(scored.emoji.primaryShortcode):"
        let work = DispatchWorkItem { [weak self] in
            self?.showPillTooltip(index: index, number: index + 1, name: name)
        }
        pillTooltipWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func showPillTooltip(index: Int, number: Int, name: String) {
        guard viewModel.isVisible, viewModel.compact else { return }
        let hosting = NSHostingView(rootView: PillTooltipLabel(number: number, name: name))
        let size = hosting.fittingSize

        let tip: NSPanel
        if let existing = tooltipPanel {
            tip = existing
        } else {
            tip = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            tip.isFloatingPanel = true
            tip.level = .floating
            tip.isOpaque = false
            tip.backgroundColor = .clear
            tip.hasShadow = true
            tip.ignoresMouseEvents = true  // never interrupt the hover
            tip.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            tooltipPanel = tip
        }
        tip.appearance = NSApp.effectiveAppearance
        tip.contentView = hosting

        // Centered above cell `index` of the pill.
        let cellCenterX = panel.frame.minX + PickerLayout.compactPadding
            + CGFloat(index) * (PickerLayout.compactCell + PickerLayout.compactSpacing)
            + PickerLayout.compactCell / 2
        var origin = CGPoint(x: cellCenterX - size.width / 2, y: panel.frame.maxY + 4)
        let screen = NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            if origin.y + size.height > visible.maxY {
                origin.y = panel.frame.minY - size.height - 4  // flip below
            }
        }
        tip.setFrame(CGRect(origin: origin, size: size), display: true)
        tip.orderFront(nil)
    }

    private func hidePillTooltip() {
        pillTooltipWork?.cancel()
        tooltipPanel?.orderOut(nil)
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
        hidePillTooltip()  // clear any stale tooltip; re-shows on hover
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

    /// Grow (or open) the panel into the full browser grid. When already on
    /// screen (the pill), it unfolds from the pill's top-left with an eased
    /// animation; otherwise it just appears at full size near the caret.
    func showExpanded(near caret: CGRect?) {
        hidePillTooltip()
        panel.appearance = NSApp.effectiveAppearance
        setCornerRadius(BrowserLayout.cornerRadius)
        let size = CGSize(width: BrowserLayout.width, height: BrowserLayout.height)

        if panel.isVisible {
            let current = panel.frame
            let target = clampToVisible(
                CGRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height),
                on: current
            )
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            let anchor = caret ?? mouseAnchor()
            let frame = positionedFrame(anchor: anchor, size: size)
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }
        viewModel.isVisible = true
        installClickMonitors()
    }

    /// Keep a frame fully on the screen that hosts `reference`.
    private func clampToVisible(_ frame: CGRect, on reference: CGRect) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(reference) }
            ?? NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        var f = frame
        if f.maxX > visible.maxX { f.origin.x = visible.maxX - f.width - 8 }
        if f.minX < visible.minX { f.origin.x = visible.minX + 8 }
        if f.maxY > visible.maxY { f.origin.y = visible.maxY - f.height - 8 }
        if f.minY < visible.minY { f.origin.y = visible.minY + 8 }
        return f
    }

    func hide() {
        panel.orderOut(nil)
        viewModel.isVisible = false
        removeClickMonitors()
        hidePillTooltip()
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

/// The pill's number-hotkey tooltip — matches the browser's glyph tooltip
/// (light box, 1px border, soft shadow) with a faint trailing hotkey digit.
private struct PillTooltipLabel: View {
    let number: Int
    let name: String

    var body: some View {
        (Text(name).foregroundStyle(.primary)
         + Text("  \(number)").foregroundStyle(.tertiary))
            .font(.system(size: 11))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15))
            )
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
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
    // Sized so the "top 8" reads as a row of 8 generous glyphs + the chevron.
    static let compactCell: CGFloat = 40
    static let compactSpacing: CGFloat = 2
    static let compactPadding: CGFloat = 6
    static var compactHeight: CGFloat { compactCell + compactPadding * 2 }
}
