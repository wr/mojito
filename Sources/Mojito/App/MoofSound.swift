import AppKit

/// Plays the bundled Quadra startup chime once. Used by the the keyword egg.
@MainActor
enum MoofSound {
    private static var player: NSSound?

    static func play() {
        guard let sound = AudioBlob.load("s06") else {
            NSSound.beep()
            return
        }
        // Retain on a static var; if it goes out of scope while playing,
        // playback stops mid-stream.
        player = sound
        sound.play()
    }
}
