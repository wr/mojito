import AppKit

@MainActor
enum ConfettiSound {
    private static var player: NSSound?

    static func play() {
        guard EggSound.effectSoundsEnabled else { return }
        guard let sound = AudioBlob.load("s07") else { return }
        player = sound
        sound.play()
    }
}
