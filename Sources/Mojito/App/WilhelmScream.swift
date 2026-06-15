import AppKit

@MainActor
enum WilhelmScream {
    private static var player: NSSound?

    static func play() {
        guard EggSound.effectSoundsEnabled else { return }
        guard let sound = AudioBlob.load("s04") else {
            NSSound.beep()
            return
        }
        player = sound
        sound.play()
    }
}
