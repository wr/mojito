import AVFoundation

/// Tiny synthesized square-wave "doo de doo" played when a brand-new
/// easter egg is discovered. Generated on the fly (no asset blob) so it
/// stays separate from the egg's own audio and adds no bundle weight.
@MainActor
enum DiscoveryFanfare {
    /// Private player so the fanfare and an egg's own audio can sound together.
    private static let player = SynthPlayer()

    /// Ascending C-major arpeggio: C5 → E5 → G5. Last note held a touch
    /// longer for the "...doo" landing. Square wave at full amplitude is
    /// harsh; the modest amplitude keeps the fanfare sitting under the
    /// egg's own sound rather than clobbering it. Rests after each note
    /// keep the inter-note gaps silent.
    private static let melody: [SynthTone] = [
        SynthTone(frequency: 523.25, duration: 0.09, amplitude: 0.06),
        SynthTone(frequency: 0, duration: 0.025, amplitude: 0),
        SynthTone(frequency: 659.25, duration: 0.09, amplitude: 0.06),
        SynthTone(frequency: 0, duration: 0.025, amplitude: 0),
        SynthTone(frequency: 783.99, duration: 0.16, amplitude: 0.06),
        SynthTone(frequency: 0, duration: 0.025, amplitude: 0),
    ]

    /// Quick attack/release — kills the click at the edges of a
    /// hard-switched square wave without softening the tone much.
    private static let envelope = SynthEnvelope(
        attackSeconds: 0.005, attackCapDivisor: 8,
        releaseSeconds: 0.020, releaseCapDivisor: 4
    )

    static func play() {
        guard let buffer = SynthRenderer.buffer(tones: melody, waveform: .square, envelope: envelope) else { return }
        player.play(buffer)
    }
}
