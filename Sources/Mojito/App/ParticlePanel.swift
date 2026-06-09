import AppKit

/// Shared borderless, non-activating overlay NSPanel for transient effect
/// surfaces (usually full-screen). Click-through by default; pass
/// `interactive: true` for overlays that take clicks or host controls.
/// `backgroundColor: nil` (the default) yields a transparent panel; a
/// color yields an opaque one.
@MainActor
enum ParticlePanel {
    /// Screen that overlays should cover.
    static func primaryScreen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    /// Full frame of the primary screen, for full-screen overlays.
    static func primaryScreenFrame() -> NSRect? {
        primaryScreen()?.frame
    }

    static func makeFullScreen(
        frame: NSRect,
        interactive: Bool = false,
        backgroundColor: NSColor? = nil,
        level: NSWindow.Level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)))
    ) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = backgroundColor != nil
        panel.backgroundColor = backgroundColor ?? .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = !interactive
        // Becomes key only if a control actually needs it, so the panel
        // still doesn't steal focus from the app the user was typing in.
        panel.becomesKeyOnlyIfNeeded = interactive
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        return panel
    }

    /// Standard end-of-effect teardown: orders the panel out and drops its
    /// content view so any frame-driven tree (TimelineView ticks,
    /// view-owned timers, animating image views) stops now rather than at
    /// some later dealloc. Overlays that animate their exit keep the
    /// content view alive through the animation and nil it themselves —
    /// don't use this for those.
    static func dismiss(_ panel: NSPanel) {
        panel.orderOut(nil)
        panel.contentView = nil
    }

    /// One-shot `willClose` observer that drops the window's content view,
    /// giving close-style effect windows the same immediate view-tree
    /// teardown as `dismiss(_:)` (a hosting view's `onDisappear` fires at
    /// close, not at some later dealloc). Bespoke close bookkeeping stays
    /// in the caller's own observer.
    static func tearDownOnClose(_ window: NSWindow) {
        let holder = ObserverHolder()
        // The notification center retains the closure, which retains the
        // holder; removing the observer on fire breaks the cycle.
        holder.token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { note in
            MainActor.assumeIsolated {
                (note.object as? NSWindow)?.contentView = nil
                if let token = holder.token {
                    NotificationCenter.default.removeObserver(token)
                    holder.token = nil
                }
            }
        }
    }

    @MainActor
    private final class ObserverHolder {
        var token: NSObjectProtocol?
    }
}
