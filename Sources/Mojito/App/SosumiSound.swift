import AppKit

@MainActor
enum SosumiSound {
    private static var player: NSSound?

    static func play() {
        guard let sound = AudioBlob.load("s01") else {
            NSSound.beep()
            return
        }
        player = sound
        sound.play()
    }
}
