import AppKit

/// Plays the bundled SpongeBob "My leg!" clip. Triggered by the keyword.
@MainActor
enum MyLegSound {
    private static var player: NSSound?

    static func play() {
        guard let sound = AudioBlob.load("s08") else {
            NSSound.beep()
            return
        }
        player = sound
        sound.play()
    }
}
