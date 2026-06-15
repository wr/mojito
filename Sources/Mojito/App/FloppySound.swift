import AppKit

@MainActor
enum FloppySound {
    private static var player: NSSound?

    static func play() {
        guard EggSound.effectSoundsEnabled else { return }
        guard let sound = AudioBlob.load("s02") else {
            NSSound.beep()
            return
        }
        player = sound
        sound.play()
    }
}
