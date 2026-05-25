import AVFoundation

/// Synthesized TNG-style warp-jump cue. Modeled on how the show's effect
/// actually behaves (per Memory Alpha / filmsound notes + isolated clips):
/// a short rev/whine into a heavy multi-layer snap, then near-silence —
/// *not* a continuous engine drone. Layout:
///
///   0.0 – 2.0s   ambient silence (impulse phase on the visual)
///   2.0 – 3.0s   whine/rev: detuned saw + bandpass-filtered noise sweeping
///                from ~200 Hz up past 1.5 kHz, exponential pitch + quadratic
///                volume so it "spins up"
///   3.0s         snap, five layers stacked:
///                  – 50 ms broadband noise crack (the high-freq "snap")
///                  – 500 ms mid body, 300 → 80 Hz pitched-down sine
///                  – 2.0 s sub fundamental at 42 Hz (the deep "whoom")
///                  – 1.2 s 84 Hz harmonic for presence
///                  – 1.5 s bandpass-filtered low noise wash (the "rumble")
///   4.0 – 10s    cruise: very faint sub-bass hum with slow LFO pulse, low
///                enough to read as "we're at warp, mostly silent"
///
/// Snap lands at `accelPeak` from `WarpHostView` so it syncs with the
/// visual's color-bloom peak. Buffer renders once and is cached.
@MainActor
enum WarpSound {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var started = false
    private static var cached: AVAudioPCMBuffer?

    private static let sampleRate: Double = 44_100
    private static let totalDuration: Double = 10.0
    private static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    // Sync points — match WarpHostView's phases.
    private static let whineStart: Double = 2.0   // == impulseEnd
    private static let snapTime:   Double = 3.0   // == accelPeak
    private static let cruiseFadeStart: Double = 4.5  // sub fundamental mostly decayed by here

    static func play() {
        guard let buffer = renderedBuffer() else { return }
        ensureRunning()
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    static func stop() {
        if player.isPlaying { player.stop() }
    }

    private static func ensureRunning() {
        guard !started else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            started = true
        } catch {
            // Visual still plays without audio if the engine fails to start.
        }
    }

    private static func renderedBuffer() -> AVAudioPCMBuffer? {
        if let buf = cached { return buf }
        let buf = renderBuffer()
        cached = buf
        return buf
    }

    private static func renderBuffer() -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let ch = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        let dt = 1.0 / sampleRate
        let twoPi = 2 * Double.pi

        // Whine oscillators (detuned saws for chorus character).
        var sawPhaseA: Double = 0
        var sawPhaseB: Double = 0

        // Biquad bandpass state, applied to white noise for the whoosh layer.
        var bpX1: Double = 0, bpX2: Double = 0
        var bpY1: Double = 0, bpY2: Double = 0

        // Snap components — five layered oscillators + a bandpass on noise
        // for the low rumble wash. Each has its own decay envelope.
        var midPhase: Double = 0
        var subFundPhase: Double = 0
        var subHarmPhase: Double = 0
        var rumbleX1: Double = 0, rumbleX2: Double = 0
        var rumbleY1: Double = 0, rumbleY2: Double = 0

        // Cruise hum.
        var cruisePhase1: Double = 0
        var cruisePhase2: Double = 0
        var cruiseLFO: Double = 0

        // Fast PRNG for noise — system random is too slow at 44.1 kHz × layers.
        var rng: UInt32 = 0xDEADBEEF
        func noise() -> Double {
            rng = rng &* 1_103_515_245 &+ 12_345
            rng &= 0x7FFF_FFFF
            return Double(rng) / Double(0x4000_0000) - 1.0
        }

        for i in 0..<Int(frameCount) {
            let t = Double(i) * dt
            var sample: Double = 0

            // ───── whine/rev (2.0 → 3.0s) ─────
            if t >= whineStart && t < snapTime {
                let p = (t - whineStart) / (snapTime - whineStart)   // 0..1

                // Exponential pitch climb: 200 → 1500 Hz. exp gives the
                // "spinning up faster and faster" feel a linear sweep can't.
                let pitchHz = 200.0 * pow(7.5, p)

                let sawA = 2.0 * (sawPhaseA - floor(sawPhaseA)) - 1.0
                let sawB = 2.0 * (sawPhaseB - floor(sawPhaseB)) - 1.0
                let toneVol = 0.16 * (p * p)                          // slow start
                sample += (sawA + sawB) * 0.5 * toneVol
                sawPhaseA += pitchHz * dt
                sawPhaseB += pitchHz * 1.007 * dt                     // ~12¢ detune
                if sawPhaseA > 1 { sawPhaseA -= 1 }
                if sawPhaseB > 1 { sawPhaseB -= 1 }

                // Biquad bandpass on white noise — center frequency rides
                // the same sweep. This is the "whoosh" layer that gives
                // the rev its character; pure sines alone sound like a
                // theremin, not an engine.
                let cutoff = 400.0 + 1300.0 * p
                let Q = 3.5
                let omega = twoPi * cutoff / sampleRate
                let cosO = cos(omega)
                let alpha = sin(omega) / (2.0 * Q)
                let a0 = 1.0 + alpha
                let bg = alpha / a0
                let yg = 2.0 * cosO / a0
                let y2g = (1.0 - alpha) / a0
                let xn = noise()
                let yn = bg * (xn - bpX2) + yg * bpY1 - y2g * bpY2
                bpX2 = bpX1; bpX1 = xn
                bpY2 = bpY1; bpY1 = yn
                let noiseVol = 0.28 * (p * p)
                sample += yn * noiseVol
            }

            // ───── snap (at t = snapTime) — multi-layered ─────
            let snapElapsed = t - snapTime
            if snapElapsed >= 0 {
                // 1. Crack: broadband noise burst, 50 ms hard decay.
                if snapElapsed < 0.05 {
                    let env = 1.0 - snapElapsed / 0.05
                    sample += noise() * 0.45 * env
                }

                // 2. Mid body: 300 → 80 Hz pitched-down sine over 100 ms,
                //    exp(-6t) decay across ~500 ms. The "punch" you hear.
                if snapElapsed < 0.5 {
                    let pitchRamp = min(1.0, snapElapsed / 0.10)
                    let midFreq = 300.0 - 220.0 * pitchRamp
                    let env = exp(-snapElapsed * 6.0)
                    sample += sin(midPhase) * env * 0.50
                    midPhase += twoPi * midFreq * dt
                }

                // 3. Sub fundamental: 42 Hz, slow decay across ~2 s. This is
                //    the "felt" component — small Mac speakers will barely
                //    reproduce it, but on headphones / a sub it's the
                //    starship-cracking-lightspeed weight.
                if snapElapsed < 2.0 {
                    let env = exp(-snapElapsed * 1.6)
                    sample += sin(subFundPhase) * env * 0.80
                    subFundPhase += twoPi * 42.0 * dt
                }

                // 4. Sub 2nd harmonic: 84 Hz, ~0.5 s decay. Adds presence so
                //    laptop speakers (which roll off below ~80 Hz) still
                //    carry the impact.
                if snapElapsed < 1.2 {
                    let env = exp(-snapElapsed * 2.5)
                    sample += sin(subHarmPhase) * env * 0.45
                    subHarmPhase += twoPi * 84.0 * dt
                }

                // 5. Low rumble wash: bandpass-filtered white noise centered
                //    at 70 Hz, wide Q, ~1.5 s decay. Stand-in for the hall-
                //    reverb tail; gives the snap a "rolling thunder" body.
                if snapElapsed < 1.5 {
                    let cutoff = 70.0
                    let Q = 1.8
                    let omega = twoPi * cutoff / sampleRate
                    let cosO = cos(omega)
                    let alpha = sin(omega) / (2.0 * Q)
                    let a0 = 1.0 + alpha
                    let bg = alpha / a0
                    let yg = 2.0 * cosO / a0
                    let y2g = (1.0 - alpha) / a0
                    let xn = noise()
                    let yn = bg * (xn - rumbleX2) + yg * rumbleY1 - y2g * rumbleY2
                    rumbleX2 = rumbleX1; rumbleX1 = xn
                    rumbleY2 = rumbleY1; rumbleY1 = yn
                    let env = exp(-snapElapsed * 1.8)
                    sample += yn * env * 0.55
                }
            }

            // ───── cruise (4.5s+) faint pulsing hum ─────
            if t >= cruiseFadeStart {
                let cruiseFadeIn = min(1.0, (t - cruiseFadeStart) / 0.6)
                let endFade = min(1.0, (totalDuration - t) / 0.5)
                let env = min(cruiseFadeIn, endFade)
                let lfo = sin(cruiseLFO)
                cruiseLFO += twoPi * 0.35 * dt
                let pulse = 1.0 + 0.35 * lfo
                let s1 = sin(cruisePhase1)
                let s2 = sin(cruisePhase2) * 0.45
                // Very low — sits under the visual rather than competing.
                sample += (s1 + s2) * 0.022 * pulse * env
                cruisePhase1 += twoPi * 55.0 * dt
                cruisePhase2 += twoPi * 82.5 * dt
                if cruisePhase1 > twoPi { cruisePhase1 -= twoPi }
                if cruisePhase2 > twoPi { cruisePhase2 -= twoPi }
            }

            if midPhase     > twoPi { midPhase     -= twoPi }
            if subFundPhase > twoPi { subFundPhase -= twoPi }
            if subHarmPhase > twoPi { subHarmPhase -= twoPi }
            if cruiseLFO    > twoPi { cruiseLFO    -= twoPi }

            // Soft-clip stacked peaks at the snap.
            sample = tanh(sample * 0.9)

            // Edge fades — kill any click at start/end.
            if t < 0.05 {
                sample *= t / 0.05
            }
            if t > totalDuration - 0.4 {
                sample *= (totalDuration - t) / 0.4
            }

            ch[i] = Float(sample)
        }
        return buffer
    }
}
