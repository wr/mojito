import AppKit

/// One of the discoverable effects. See `EasterEgg` for the
/// (opaque) identity; the trigger keyword is decoded at runtime from
/// `EggStrings` and not present in source.
@MainActor
enum ConfettiSound {
    private static var player: NSSound?

    static func play() {
        guard let sound = AudioBlob.load("s07") else { return }
        player = sound
        sound.play()
    }
}
