import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Pause Mojito for 1 hour. Pressing the same shortcut again while paused
    /// resumes immediately, regardless of how the pause was initiated.
    static let pauseHour = Self("pauseHour")

    /// Pause Mojito until 7am tomorrow. Pressing the same shortcut again
    /// while paused resumes immediately.
    static let pauseUntilTomorrow = Self("pauseUntilTomorrow")

    /// Global hotkey that opens (and closes) the full emoji browser anywhere.
    /// Defaults to ⌃⌥Space; "Replace System Picker" swaps it to ⌃⌘Space, and the
    /// reset button restores the default. Set in Settings ▸ General ▸ Quick Access.
    static let showEmojiBrowser = Self("showEmojiBrowser",
                                       default: .init(.space, modifiers: [.control, .option]))
}
