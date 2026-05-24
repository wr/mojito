import AppKit

@MainActor
enum Rickroll {
    static func go() {
        if let url = URL(string: "https://youtu.be/dQw4w9WgXcQ") {
            NSWorkspace.shared.open(url)
        }
    }
}
