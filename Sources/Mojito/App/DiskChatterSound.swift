import AVFoundation

/// Rhythmic disk-head chatter — the *chk chk … chiddle chk* of a spinning
/// drive seeking clusters. No sample: short filtered-noise bursts and the
/// occasional stepper-motor chirp are synthesized once, then dealt out on a
/// jittery timer so the cadence never reads as an obvious loop. Runs until
/// `stop()`.
@MainActor
enum DiskChatterSound {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var started = false
    private static var active = false
    /// Bumped on every start/stop so stale timer closures no-op.
    private static var generation = 0

    private static let sampleRate: Double = 44_100
    private static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    private static var ticks: [AVAudioPCMBuffer] = []
    private static var chatter: AVAudioPCMBuffer?
    private static var chirp: AVAudioPCMBuffer?

    static func start() {
        ensureBuffers()
        ensureRunning()
        guard !active else { return }   // re-trigger: let the run continue
        active = true
        generation += 1
        if !player.isPlaying { player.play() }
        scheduleNext(gen: generation)
    }

    static func stop() {
        guard active else { return }
        active = false
        generation += 1
        player.stop()
    }

    private static func ensureRunning() {
        guard !started else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            started = true
        } catch {
            // Silent fall-through; the visual still plays.
        }
    }

    private static func scheduleNext(gen: Int) {
        guard active, gen == generation else { return }

        let roll = Int.random(in: 0..<12)
        let buffer: AVAudioPCMBuffer?
        if roll == 0 { buffer = chirp }
        else if roll < 3 { buffer = chatter }
        else { buffer = ticks.randomElement() }

        if let buffer {
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }

        // Mostly brisk ticks with an occasional pause for the "…" beat.
        let interval = (Int.random(in: 0..<8) == 0)
            ? Double.random(in: 0.45...0.85)
            : Double.random(in: 0.09...0.22)
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            MainActor.assumeIsolated { scheduleNext(gen: gen) }
        }
    }

    // MARK: - Synthesis

    private static func ensureBuffers() {
        guard ticks.isEmpty else { return }
        // A few "chk" variants: short noise bursts, decaying fast, each with
        // a slightly different pitch tint so repeats don't sound identical.
        ticks = [
            makeTick(duration: 0.030, decay: 140, tint: 1900),
            makeTick(duration: 0.026, decay: 170, tint: 2300),
            makeTick(duration: 0.038, decay: 110, tint: 1500),
        ].compactMap { $0 }
        chatter = makeChatter()
        chirp = makeChirp()
    }

    /// Single click: white noise shaped by a one-pole low-pass (the `tint`
    /// cutoff) under an exponential-decay envelope.
    private static func makeTick(duration: Double, decay: Double, tint: Double) -> AVAudioPCMBuffer? {
        let frames = Int(duration * sampleRate)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)

        // One-pole LPF coefficient from cutoff frequency.
        let rc = 1.0 / (2.0 * Double.pi * tint)
        let dt = 1.0 / sampleRate
        let alpha = Float(dt / (rc + dt))
        var lp: Float = 0
        let amplitude: Float = 0.22

        for i in 0..<frames {
            let noise = Float.random(in: -1...1)
            lp += alpha * (noise - lp)
            let env = Float(exp(-decay * Double(i) / sampleRate))
            channel[i] = lp * env * amplitude
        }
        return buffer
    }

    /// "Chiddle": three very fast clicks in one buffer — the rapid head step.
    private static func makeChatter() -> AVAudioPCMBuffer? {
        let clickDur = 0.018
        let stride = 0.024
        let total = stride * 3
        let frames = Int(total * sampleRate)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        for i in 0..<frames { channel[i] = 0 }

        let clickFrames = Int(clickDur * sampleRate)
        let strideFrames = Int(stride * sampleRate)
        let rc = 1.0 / (2.0 * Double.pi * 2100)
        let dt = 1.0 / sampleRate
        let alpha = Float(dt / (rc + dt))
        let amplitude: Float = 0.18

        for c in 0..<3 {
            let base = c * strideFrames
            var lp: Float = 0
            for i in 0..<clickFrames where base + i < frames {
                let noise = Float.random(in: -1...1)
                lp += alpha * (noise - lp)
                let env = Float(exp(-150 * Double(i) / sampleRate))
                channel[base + i] = lp * env * amplitude
            }
        }
        return buffer
    }

    /// Stepper-motor seek: a short descending sine sweep with a hint of decay.
    private static func makeChirp() -> AVAudioPCMBuffer? {
        let duration = 0.085
        let frames = Int(duration * sampleRate)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)

        let f0 = 1300.0, f1 = 480.0
        let amplitude: Float = 0.10
        var phase = 0.0
        for i in 0..<frames {
            let frac = Double(i) / Double(frames)
            let freq = f0 + (f1 - f0) * frac
            phase += freq / sampleRate
            if phase >= 1 { phase -= 1 }
            let env = Float(exp(-9 * frac))
            channel[i] = Float(sin(2 * Double.pi * phase)) * env * amplitude
        }
        return buffer
    }
}
