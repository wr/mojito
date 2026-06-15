import AppKit

@MainActor
enum MyLegSound {
    private static var player: NSSound?

    static func play() {
        guard EggSound.effectSoundsEnabled else { return }
        guard let sound = AudioBlob.load("s08") else {
            NSSound.beep()
            return
        }
        player = sound
        sound.play()
    }
}
