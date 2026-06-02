import AVFoundation

/// Synthesized 8-bit SFX for the guessing game. Soft triangle tones rendered
/// on the fly (no asset blobs), on a private engine separate from
/// `DiscoveryFanfare` so a win chime and the egg fanfare can sound together.
@MainActor
enum WordleSounds {
    enum RevealTone { case hit, near, miss }

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

    private struct Tone {
        var freq: Double          // <= 0 renders as a silent rest
        var duration: Double
        var amplitude: Float = 0.07
    }

    // MARK: SFX

    static func tick() {
        play([Tone(freq: 1_100, duration: 0.022, amplitude: 0.045)])
    }

    // `step` is the 0-based ordinal of this tile among correct tiles in the row;
    // near/miss tiles ignore it (semitone offset 0).
    static func reveal(_ tone: RevealTone, step: Int = 0) {
        let base: Double
        switch tone {
        case .hit:  base = 880      // A5
        case .near: base = 622.25   // D#5
        case .miss: base = 415.30   // G#4
        }
        // Major-triad semitone offsets (A C# E A C# …). Clamped past the top.
        let degrees = [0, 4, 7, 12, 16, 19, 24]
        let semis = tone == .hit ? degrees[min(max(step, 0), degrees.count - 1)] : 0
        let freq = base * pow(2.0, Double(semis) / 12.0)
        play([Tone(freq: freq, duration: 0.10, amplitude: 0.06)])
    }

    static func invalid() {
        // Low descending "bzzt".
        play([
            Tone(freq: 174.61, duration: 0.09, amplitude: 0.08),
            Tone(freq: 138.59, duration: 0.12, amplitude: 0.08),
        ])
    }

    static func win() {
        // Ascending C-major arpeggio landing an octave up.
        play([
            Tone(freq: 523.25, duration: 0.09),
            Tone(freq: 659.25, duration: 0.09),
            Tone(freq: 783.99, duration: 0.09),
            Tone(freq: 1_046.50, duration: 0.18),
        ])
    }

    static func lose() {
        // Slow descending minor sigh.
        play([
            Tone(freq: 392.00, duration: 0.15),
            Tone(freq: 329.63, duration: 0.15),
            Tone(freq: 261.63, duration: 0.26),
        ])
    }

    static func bonusWin() {
        // Bigger flourish: run up, brief rest, then a triumphant top triplet.
        play([
            Tone(freq: 523.25, duration: 0.075),
            Tone(freq: 659.25, duration: 0.075),
            Tone(freq: 783.99, duration: 0.075),
            Tone(freq: 1_046.50, duration: 0.075),
            Tone(freq: 0, duration: 0.05),
            Tone(freq: 1_046.50, duration: 0.07),
            Tone(freq: 1_318.51, duration: 0.07),
            Tone(freq: 1_567.98, duration: 0.22),
        ])
    }

    // MARK: synthesis

    private static func play(_ tones: [Tone]) {
        guard let buffer = render(tones) else { return }
        ensureRunning()
        guard started else { return }
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
            // No audio if the engine won't start — gameplay is unaffected.
        }
    }

    private static func render(_ tones: [Tone]) -> AVAudioPCMBuffer? {
        let total = tones.reduce(0) { $0 + $1.duration }
        let frameCount = AVAudioFrameCount(max(1, total * sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        var cursor = 0
        for tone in tones {
            let noteFrames = Int(tone.duration * sampleRate)
            // Short attack/release tames the click at the note edges. The
            // triangle wave is mellower than a square — same simple chiptune
            // shape, less of the harsh buzz.
            let attack = min(noteFrames / 8, Int(0.004 * sampleRate))
            let release = min(noteFrames / 3, Int(0.02 * sampleRate))
            var phase: Double = 0
            for i in 0..<noteFrames {
                guard cursor + i < Int(frameCount) else { break }
                var env: Float = 1
                if i < attack {
                    env = Float(i) / Float(max(1, attack))
                } else if i > noteFrames - release {
                    env = Float(noteFrames - i) / Float(max(1, release))
                }
                let sample: Float = tone.freq <= 0 ? 0 : Float(4 * abs(phase - 0.5) - 1)
                channel[cursor + i] = sample * tone.amplitude * env
                phase += tone.freq / sampleRate
                if phase >= 1 { phase -= 1 }
            }
            cursor += noteFrames
        }
        return buffer
    }
}
