import SwiftUI

/// Cross-cutting navigation requests into the Settings window. Right now the
/// only request is "reveal this egg": select the Easter eggs tab, scroll the
/// row into view, and flash it. Driven from the discovery banner (which posts
/// `.mojitoRevealEasterEgg`, forwarded by `AppDelegate`) so a freshly found
/// egg is one click from its Settings entry.
///
/// Requests are *consumed* (cleared back to nil) by the views that apply them,
/// so opening Settings the normal way still lands on the default tab and never
/// re-triggers a stale flash.
@MainActor
final class SettingsNavigator: ObservableObject {
    static let shared = SettingsNavigator()

    /// Egg to scroll-to-and-flash. The nonce lets the *same* egg re-trigger a
    /// flash on a second click (the id alone wouldn't change).
    struct Reveal: Equatable {
        let eggID: String
        let nonce: Int
    }

    @Published var requestedTab: SettingsRoot.Tab?
    @Published var reveal: Reveal?

    private var nonce = 0

    func revealEgg(_ id: String) {
        nonce += 1
        requestedTab = .easterEggs
        reveal = Reveal(eggID: id, nonce: nonce)
    }
}

extension Notification.Name {
    /// `object` is the egg's raw id (`String`). Posted by the discovery banner.
    static let mojitoRevealEasterEgg = Notification.Name("mojitoRevealEasterEgg")
}
