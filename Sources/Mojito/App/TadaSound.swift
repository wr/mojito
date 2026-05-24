import AppKit

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
