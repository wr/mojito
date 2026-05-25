import AVFoundation

/// Tiny synthesized square-wave "doo de doo" played when a brand-new
/// easter egg is discovered. Generated on the fly (no asset blob) so it
/// stays separate from the egg's own audio and adds no bundle weight.
@MainActor
enum DiscoveryFanfare {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var started = false

    private static let sampleRate: Double = 44_100
    private static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    /// Ascending C-major arpeggio: C5 → E5 → G5. Last note held a touch
    /// longer for the "...doo" landing.
    private static let melody: [(freq: Double, duration: Double)] = [
        (523.25, 0.09),
        (659.25, 0.09),
        (783.99, 0.16),
    ]
    private static let gap: Double = 0.025
    /// Square wave at full amplitude is harsh; keep the fanfare modest so
    /// it sits under the egg's own sound rather than clobbering it.
    private static let amplitude: Float = 0.06

    static func play() {
        guard let buffer = renderBuffer() else { return }
        ensureRunning()
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private static func ensureRunning() {
        guard !started else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            started = true
        } catch {
            // If the engine can't start (rare), silently skip — discovery
            // banner still fires, just without audio.
        }
    }

    private static func renderBuffer() -> AVAudioPCMBuffer? {
        let totalDuration = melody.reduce(0) { $0 + $1.duration + gap }
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        // Zero-fill first so the inter-note gaps are silent.
        for i in 0..<Int(frameCount) { channel[i] = 0 }

        var cursor = 0
        for note in melody {
            let noteFrames = Int(note.duration * sampleRate)
            let phaseInc = note.freq / sampleRate
            // Quick attack/release in frames — kills the click at edges of
            // a hard-switched square wave without softening the tone much.
            let attack = min(noteFrames / 8, Int(0.005 * sampleRate))
            let release = min(noteFrames / 4, Int(0.020 * sampleRate))
            var phase: Double = 0
            for i in 0..<noteFrames {
                let square: Float = phase < 0.5 ? 1 : -1
                var env: Float = 1
                if i < attack {
                    env = Float(i) / Float(attack)
                } else if i > noteFrames - release {
                    env = Float(noteFrames - i) / Float(release)
                }
                channel[cursor + i] = square * amplitude * env
                phase += phaseInc
                if phase >= 1 { phase -= 1 }
            }
            cursor += noteFrames + Int(gap * sampleRate)
        }
        return buffer
    }
}
