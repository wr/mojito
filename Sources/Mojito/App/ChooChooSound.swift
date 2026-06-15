import AVFoundation

/// Two-blast train whistle — perfect-fifth (G4 + D5) triangle chord, no sample.
@MainActor
enum ChooChooSound {
    private static let player = SynthPlayer()
    private static let sampleRate = SynthRenderer.sampleRate

    /// Two short blasts. Second is held a touch longer so it lands.
    private static let blasts: [(duration: Double, gap: Double)] = [
        (0.28, 0.10),
        (0.42, 0.00),
    ]
    /// Fifth interval — classic whistle voicing.
    private static let voices: [Double] = [392.00, 587.33]
    private static let amplitude: Float = 0.12

    static func play() {
        guard EggSound.effectSoundsEnabled else { return }
        guard let buffer = renderBuffer() else { return }
        player.play(buffer)
    }

    /// Multi-voice chord with a long per-blast release — bespoke enough to
    /// stay out of the single-voice `SynthRenderer.buffer` path.
    private static func renderBuffer() -> AVAudioPCMBuffer? {
        let totalDuration = blasts.reduce(0) { $0 + $1.duration + $1.gap }
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: SynthRenderer.monoFormat, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount
        for i in 0..<Int(frameCount) { channel[i] = 0 }

        var phases = [Double](repeating: 0, count: voices.count)
        var cursor = 0
        for blast in blasts {
            let noteFrames = Int(blast.duration * sampleRate)
            // Long release gives the "wooo" tail that reads as a whistle, not a beep.
            let attack = min(noteFrames / 6, Int(0.015 * sampleRate))
            let release = min(noteFrames / 2, Int(0.18 * sampleRate))
            let phaseIncs = voices.map { $0 / sampleRate }
            let perVoice = amplitude / Float(voices.count)
            for i in 0..<noteFrames {
                var sample: Float = 0
                for v in 0..<voices.count {
                    // Triangle wave: smoother than square, more body than sine.
                    let p = phases[v]
                    let tri = Float(p < 0.5 ? (4 * p - 1) : (3 - 4 * p))
                    sample += tri * perVoice
                    phases[v] = p + phaseIncs[v]
                    if phases[v] >= 1 { phases[v] -= 1 }
                }
                var env: Float = 1
                if i < attack {
                    env = Float(i) / Float(attack)
                } else if i > noteFrames - release {
                    env = Float(noteFrames - i) / Float(release)
                }
                channel[cursor + i] = sample * env
            }
            cursor += noteFrames + Int(blast.gap * sampleRate)
        }
        return buffer
    }
}
