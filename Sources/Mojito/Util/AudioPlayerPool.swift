import AVFoundation

/// Fixed-size pool of `AVAudioPlayer`s over one sound, so rapid
/// retriggers overlap instead of cutting each other off. Prefers an idle
/// player; falls back to round-robin (restarting the chosen player) when
/// all are busy.
@MainActor
final class AudioPlayerPool {
    private let players: [AVAudioPlayer]
    private var nextIndex = 0

    init(data: Data, size: Int, volume: Float) {
        players = (0..<size).compactMap { _ in
            guard let p = try? AVAudioPlayer(data: data) else { return nil }
            p.volume = volume
            p.prepareToPlay()
            return p
        }
    }

    func play() {
        guard !players.isEmpty else { return }
        let player: AVAudioPlayer
        if let idle = players.first(where: { !$0.isPlaying }) {
            player = idle
        } else {
            player = players[nextIndex % players.count]
            nextIndex &+= 1
        }
        player.stop()
        player.currentTime = 0
        player.play()
    }
}
