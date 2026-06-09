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
}
