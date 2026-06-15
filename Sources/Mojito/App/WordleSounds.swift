import AVFoundation

/// Synthesized 8-bit SFX for the guessing game. Soft triangle tones rendered
/// on the fly (no asset blobs), on a private player separate from
/// `DiscoveryFanfare` so a win chime and the egg fanfare can sound together.
@MainActor
enum WordleSounds {
    enum RevealTone { case hit, near, miss }

    private static let player = SynthPlayer()

    /// Short attack/release tames the click at the note edges. The
    /// triangle wave is mellower than a square — same simple chiptune
    /// shape, less of the harsh buzz.
    private static let envelope = SynthEnvelope(
        attackSeconds: 0.004, attackCapDivisor: 8,
        releaseSeconds: 0.02, releaseCapDivisor: 3
    )

    private static func tone(_ freq: Double, _ duration: Double, _ amplitude: Float = 0.07) -> SynthTone {
        SynthTone(frequency: freq, duration: duration, amplitude: amplitude)
    }

    // MARK: SFX

    static func tick() {
        play([tone(1_100, 0.022, 0.045)])
    }

    // `step` is the 0-based ordinal of this tile among correct tiles in the row;
    // near/miss tiles ignore it (semitone offset 0).
    static func reveal(_ revealTone: RevealTone, step: Int = 0) {
        let base: Double
        switch revealTone {
        case .hit:  base = 880      // A5
        case .near: base = 622.25   // D#5
        case .miss: base = 415.30   // G#4
        }
        // Major-triad semitone offsets (A C# E A C# …). Clamped past the top.
        let degrees = [0, 4, 7, 12, 16, 19, 24]
        let semis = revealTone == .hit ? degrees[min(max(step, 0), degrees.count - 1)] : 0
        let freq = base * pow(2.0, Double(semis) / 12.0)
        play([tone(freq, 0.10, 0.06)])
    }

    static func invalid() {
        // Low descending "bzzt".
        play([
            tone(174.61, 0.09, 0.08),
            tone(138.59, 0.12, 0.08),
        ])
    }

    static func win() {
        // Ascending C-major arpeggio landing an octave up.
        play([
            tone(523.25, 0.09),
            tone(659.25, 0.09),
            tone(783.99, 0.09),
            tone(1_046.50, 0.18),
        ])
    }

    static func lose() {
        // Slow descending minor sigh.
        play([
            tone(392.00, 0.15),
            tone(329.63, 0.15),
            tone(261.63, 0.26),
        ])
    }

    static func bonusWin() {
        // Bigger flourish: run up, brief rest, then a triumphant top triplet.
        play([
            tone(523.25, 0.075),
            tone(659.25, 0.075),
            tone(783.99, 0.075),
            tone(1_046.50, 0.075),
            tone(0, 0.05),
            tone(1_046.50, 0.07),
            tone(1_318.51, 0.07),
            tone(1_567.98, 0.22),
        ])
    }

    private static func play(_ tones: [SynthTone]) {
        guard EggSound.effectSoundsEnabled else { return }
        guard let buffer = SynthRenderer.buffer(tones: tones, waveform: .triangle, envelope: envelope) else { return }
        player.play(buffer)
    }
}
