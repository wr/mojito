import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Pause Mojito for 1 hour. Pressing the same shortcut again while paused
    /// resumes immediately, regardless of how the pause was initiated.
    static let pauseHour = Self("pauseHour")

    /// Pause Mojito until 7am tomorrow. Pressing the same shortcut again
    /// while paused resumes immediately.
    static let pauseUntilTomorrow = Self("pauseUntilTomorrow")

    /// Global hotkey that opens the full emoji browser anywhere. Defaults to
    /// ⌃⌘Space — the same chord macOS uses for its Character Viewer, so Mojito's
    /// browser takes its place. (macOS may still claim it until the system
    /// "Emoji & Symbols" shortcut is turned off in System Settings ▸ Keyboard.)
    static let showEmojiBrowser = Self("showEmojiBrowser", default: .init(.space, modifiers: [.command, .control]))
}
