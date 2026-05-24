import AppKit

/// One of the discoverable effects. See `EasterEgg` for the
/// (opaque) identity; the trigger keyword is decoded at runtime from
/// `EggStrings` and not present in source.
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
