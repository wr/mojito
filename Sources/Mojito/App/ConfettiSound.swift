import AppKit

/// Plays the bundled confetti chime once. Used by the the keyword egg.
@MainActor
enum ConfettiSound {
    private static var player: NSSound?

    static func play() {
        guard let sound = AudioBlob.load("s07") else { return }
        player = sound
        sound.play()
    }
}
