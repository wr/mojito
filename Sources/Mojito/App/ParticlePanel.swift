import AppKit

/// Shared full-screen, click-through, statusWindow-level NSPanel used by both
/// `EmojiRain` and `ConfettiRain`.
@MainActor
enum ParticlePanel {
    static func makeFullScreen(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        return panel
    }
}
