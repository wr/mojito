import AVFoundation

/// Mechanical disk-head chatter — the "chk … chk chk" of a drive seeking
/// clusters. No samples: short noise-transient-over-resonant-body clicks are
/// synthesized once, then fired on demand by the optimizer (one per
/// consolidated chunk) so the cadence tracks the on-screen defrag instead of a
/// free-running loop.
@MainActor
enum DiskChatterSound {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var started = false
    /// Gates playback so ticks queued by a still-running view stop the instant
    /// the effect is dismissed.
    private static var enabled = false

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

    /// Stand up the engine so subsequent `playTick`/`playRun` are instant.
    static func start() {
        ensureBuffers()
        ensureRunning()
        enabled = true
        guard started, !player.isPlaying else { return }
        player.play()
    }

    static func stop() {
        enabled = false
        guard started else { return }
        player.stop()
    }

    /// One head tick — call once per small consolidated chunk.
    static func playTick() {
        guard enabled else { return }
        ensureRunning()
        guard started, let buffer = ticks.randomElement() else { return }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// A rapid run — call for a big relocation band.
    static func playRun() {
        guard enabled else { return }
        ensureRunning()
        guard started, let buffer = (Bool.random() ? chirp : chatter) else { return }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
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
            // Silent fall-through; the visual still plays.
        }
    }

    // MARK: - Synthesis

    private static func ensureBuffers() {
        guard ticks.isEmpty else { return }
        // A few "chk" variants — a noise transient over a short resonant body,
        // so each reads as a mechanical head tick rather than a hiss. Quiet.
        // Eight "chk" variants — higher cutoffs + faster decays read clickier;
        // the resonant body is high and brief so it never goes "farty".
        ticks = [
            makeClick(duration: 0.024, lpCutoff: 2300, noiseDecay: 520, bodyFreq: 1050, bodyDecay: 540, amp: 0.090),
            makeClick(duration: 0.021, lpCutoff: 2700, noiseDecay: 600, bodyFreq: 1200, bodyDecay: 600, amp: 0.085),
            makeClick(duration: 0.028, lpCutoff: 2000, noiseDecay: 460, bodyFreq: 920, bodyDecay: 480, amp: 0.090),
            makeClick(duration: 0.019, lpCutoff: 3000, noiseDecay: 680, bodyFreq: 1380, bodyDecay: 680, amp: 0.078),
            makeClick(duration: 0.026, lpCutoff: 2200, noiseDecay: 500, bodyFreq: 990, bodyDecay: 520, amp: 0.088),
            makeClick(duration: 0.022, lpCutoff: 2550, noiseDecay: 560, bodyFreq: 1140, bodyDecay: 560, amp: 0.082),
            makeClick(duration: 0.030, lpCutoff: 1850, noiseDecay: 420, bodyFreq: 860, bodyDecay: 440, amp: 0.090),
            makeClick(duration: 0.020, lpCutoff: 2850, noiseDecay: 640, bodyFreq: 1300, bodyDecay: 640, amp: 0.076),
        ].compactMap { $0 }
        chatter = makeRun(clicks: 4, stride: 0.020, clickDur: 0.013, baseFreq: 900, step: 40, amp: 0.075)
        chirp   = makeRun(clicks: 6, stride: 0.015, clickDur: 0.011, baseFreq: 1000, step: 80, amp: 0.065)
    }

    /// One mechanical click: a brief filtered-noise transient summed with a
    /// fast-decaying resonant "body" (the casing thunk). The low cutoff keeps
    /// it muffled rather than hissy; amplitudes are deliberately modest.
    private static func makeClick(duration: Double, lpCutoff: Double, noiseDecay: Double, bodyFreq: Double, bodyDecay: Double, amp: Float) -> AVAudioPCMBuffer? {
        let frames = Int(duration * sampleRate)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)

        let rc = 1.0 / (2.0 * Double.pi * lpCutoff)
        let dt = 1.0 / sampleRate
        let alpha = Float(dt / (rc + dt))
        var lp: Float = 0
        var phase = 0.0

        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let noise = Float.random(in: -1...1)
            lp += alpha * (noise - lp)
            let nEnv = Float(exp(-noiseDecay * t))
            phase += bodyFreq / sampleRate
            if phase >= 1 { phase -= 1 }
            let body = Float(sin(2 * Double.pi * phase)) * Float(exp(-bodyDecay * t))
            // Noise-dominant click; the body is just a faint high "k", never a
            // low ringing tone (which reads as "farty").
            channel[i] = (lp * nEnv * 0.88 + body * 0.12) * amp
        }
        return buffer
    }

    /// A run of fast descending clicks: "chiddle" (short run) or a longer head
    /// seek. Grittier than a clean tone.
    private static func makeRun(clicks: Int, stride: Double, clickDur: Double, baseFreq: Double, step: Double, amp: Float) -> AVAudioPCMBuffer? {
        let total = stride * Double(clicks)
        let frames = Int(total * sampleRate)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        for i in 0..<frames { channel[i] = 0 }

        let rc = 1.0 / (2.0 * Double.pi * 1300)
        let dt = 1.0 / sampleRate
        let alpha = Float(dt / (rc + dt))
        let strideFrames = Int(stride * sampleRate)
        let clickFrames = Int(clickDur * sampleRate)

        for c in 0..<clicks {
            let base = c * strideFrames
            var lp: Float = 0
            var phase = 0.0
            let bodyFreq = max(90, baseFreq - Double(c) * step)
            for i in 0..<clickFrames where base + i < frames {
                let t = Double(i) / sampleRate
                let noise = Float.random(in: -1...1)
                lp += alpha * (noise - lp)
                let nEnv = Float(exp(-420 * t))
                phase += bodyFreq / sampleRate
                if phase >= 1 { phase -= 1 }
                let body = Float(sin(2 * Double.pi * phase)) * Float(exp(-400 * t))
                channel[base + i] = (lp * nEnv * 0.88 + body * 0.12) * amp
            }
        }
        return buffer
    }
}
