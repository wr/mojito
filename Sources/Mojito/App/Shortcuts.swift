import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Pause Mojito for 1 hour. Pressing the same shortcut again while paused
    /// resumes immediately, regardless of how the pause was initiated.
    static let pauseHour = Self("pauseHour")

    /// Pause Mojito until 7am tomorrow. Pressing the same shortcut again
    /// while paused resumes immediately.
    static let pauseUntilTomorrow = Self("pauseUntilTomorrow")

    /// Global hotkey that opens the full emoji browser anywhere. No default —
    /// the user assigns it in Settings ▸ Favorites.
    static let showEmojiBrowser = Self("showEmojiBrowser")
}
