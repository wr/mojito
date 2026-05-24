import AppKit

/// One of the discoverable effects. See `EasterEgg` for the
/// (opaque) identity; the trigger keyword is decoded at runtime from
/// `EggStrings` and not present in source.
@MainActor
enum Rickroll {
    static func go() {
        if let url = URL(string: "https://youtu.be/dQw4w9WgXcQ") {
            NSWorkspace.shared.open(url)
        }
    }
}
