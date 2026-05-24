import AppKit

/// Plays the Windows tada chime. Triggered by the keyword. No visual.
@MainActor
enum TadaSound {
    private static var player: NSSound?

    static func play() {
        guard let sound = AudioBlob.load("s05") else {
            NSSound.beep()
            return
        }
        player = sound
        sound.play()
    }
}
