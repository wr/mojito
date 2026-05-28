import AppKit

/// Shared full-screen, statusWindow-level NSPanel. Click-through by default
/// (`EmojiRain`, `ConfettiRain`); pass `interactive: true` for effects that
/// host real controls (the disk optimizer's buttons).
@MainActor
enum ParticlePanel {
    static func makeFullScreen(frame: NSRect, interactive: Bool = false) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = !interactive
        // Becomes key only if a control actually needs it, so the panel still
        // doesn't steal focus from the app the user triggered the egg in.
        panel.becomesKeyOnlyIfNeeded = interactive
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        return panel
    }
}
