import AppKit

@MainActor
enum MoofSound {
    private static var player: NSSound?

    static func play() {
        guard let sound = AudioBlob.load("s06") else {
            NSSound.beep()
            return
        }
        // Retain on a static var — NSSound stops mid-stream if released.
        player = sound
        sound.play()
    }
}
