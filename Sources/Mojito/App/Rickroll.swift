import AppKit

/// Opens the canonical rickroll URL in the default browser. Triggered by
/// the keyword. No window, no asset — just `NSWorkspace.open`.
@MainActor
enum Rickroll {
    static func go() {
        if let url = URL(string: "https://youtu.be/dQw4w9WgXcQ") {
            NSWorkspace.shared.open(url)
        }
    }
}
