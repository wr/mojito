import AppKit

@MainActor
enum ConfettiSound {
    private static var player: NSSound?

    static func play() {
        guard let sound = AudioBlob.load("s07") else { return }
        player = sound
        sound.play()
    }
}
