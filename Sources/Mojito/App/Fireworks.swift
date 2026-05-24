import AppKit
import AVFoundation
import SwiftUI

/// Rising colored shells that explode into a sphere of falling sparks,
/// plus a few secondary pops per burst for a layered "crackle" feel.
/// Each pop is paired with a synthesized "pew" tone pitched off a
/// pentatonic scale so overlapping bursts sound musical.
@MainActor
enum Fireworks {
    private static var activeWindow: NSWindow?

    static func start(burstCount: Int = 14, duration: TimeInterval = 6.0) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        activeWindow?.orderOut(nil)
        activeWindow = nil

        let colors: [Color] = [
            .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .mint, .white
        ]

        var bursts: [Burst] = []
        bursts.reserveCapacity(burstCount)
        for i in 0..<burstCount {
            let center = CGPoint(
                x: .random(in: frame.width * 0.12...frame.width * 0.88),
                y: .random(in: frame.height * 0.12...frame.height * 0.45)
            )
            // ~14 bursts packed into ~5s; last shell pops just before
            // total `duration`.
            let launchAt = TimeInterval(i) * 0.32 + .random(in: 0...0.18)
            let color = colors.randomElement() ?? .red
            let sparkCount = Int.random(in: 90...130)
            var sparks: [Spark] = []
            sparks.reserveCapacity(sparkCount)
            for _ in 0..<sparkCount {
                let angle = Double.random(in: 0..<(2 * .pi))
                let speed: CGFloat = .random(in: 360...720)
                sparks.append(Spark(
                    vx: CGFloat(cos(angle)) * speed,
                    vy: CGFloat(sin(angle)) * speed,
                    twinkle: .random(in: 0..<(.pi * 2))
                ))
            }
            // Glittery sparkles — smaller, denser, shorter-lived.
            let twinkleCount = Int.random(in: 30...50)
            var twinkles: [Spark] = []
            twinkles.reserveCapacity(twinkleCount)
            for _ in 0..<twinkleCount {
                let angle = Double.random(in: 0..<(2 * .pi))
                let speed: CGFloat = .random(in: 80...240)
                twinkles.append(Spark(
                    vx: CGFloat(cos(angle)) * speed,
                    vy: CGFloat(sin(angle)) * speed,
                    twinkle: .random(in: 0..<(.pi * 2))
                ))
            }
            var secondaries: [SecondaryBurst] = []
            let secondaryCount = Int.random(in: 2...3)
            for _ in 0..<secondaryCount {
                let offset = CGPoint(
                    x: .random(in: -90...90),
                    y: .random(in: -60...60)
                )
                let delay: TimeInterval = .random(in: 0.18...0.45)
                let secondaryColor = colors.randomElement() ?? color
                var secondarySparks: [Spark] = []
                let count = Int.random(in: 16...28)
                for _ in 0..<count {
                    let angle = Double.random(in: 0..<(2 * .pi))
                    let speed: CGFloat = .random(in: 120...260)
                    secondarySparks.append(Spark(
                        vx: CGFloat(cos(angle)) * speed,
                        vy: CGFloat(sin(angle)) * speed,
                        twinkle: .random(in: 0..<(.pi * 2))
                    ))
                }
                secondaries.append(SecondaryBurst(
                    offset: offset,
                    delay: delay,
                    color: secondaryColor,
                    sparks: secondarySparks
                ))
            }
            // Pentatonic-ish so overlapping bursts stay pleasant.
            let pewFreqs: [Double] = [440, 523, 587, 659, 784, 880, 988]
            bursts.append(Burst(
                startX: center.x,
                peakY: center.y,
                launchTime: launchAt,
                color: color,
                sparks: sparks,
                twinkles: twinkles,
                secondaries: secondaries,
                pewFrequency: pewFreqs.randomElement() ?? 523
            ))
        }

        let panel = ParticlePanel.makeFullScreen(frame: frame)
        let host = NSHostingView(rootView: FireworksView(
            bursts: bursts,
            startDate: Date(),
            bounds: frame.size
        ))
        host.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = host
        panel.orderFrontRegardless()
        activeWindow = panel

        var cancelToken: (() -> Void)?
        let dismiss = {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                cancelToken?(); cancelToken = nil
                if activeWindow === panel { activeWindow = nil }
            }
        }
        cancelToken = EffectDismisser.register(dismiss)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            MainActor.assumeIsolated { dismiss() }
        }
    }
}

private struct Spark {
    let vx: CGFloat
    let vy: CGFloat
    /// Phase offset so neighboring sparks don't blink in lock-step.
    let twinkle: Double
}

private struct SecondaryBurst {
    let offset: CGPoint
    let delay: TimeInterval
    let color: Color
    let sparks: [Spark]
}

private struct Burst {
    let startX: CGFloat
    let peakY: CGFloat
    let launchTime: TimeInterval
    let color: Color
    let sparks: [Spark]
    let twinkles: [Spark]
    let secondaries: [SecondaryBurst]
    let pewFrequency: Double
}

private struct FireworksView: View {
    let bursts: [Burst]
    let startDate: Date
    let bounds: CGSize

    private let riseTime: TimeInterval = 0.85
    private let sparkLifetime: TimeInterval = 1.9
    private let twinkleLifetime: TimeInterval = 0.9
    /// px/s².
    private let sparkGravity: CGFloat = 380

    /// Mutated from the `onChange` below to fire each pew tone once.
    @State private var poppedIndices: Set<Int> = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)

            ZStack {
                // Per-burst sky flash, ~250ms. Stacks across overlapping
                // bursts so a salvo washes the screen.
                ForEach(Array(bursts.enumerated()), id: \.offset) { _, burst in
                    let t = elapsed - burst.launchTime - riseTime
                    if t >= 0 && t < 0.25 {
                        burst.color
                            .opacity(0.05 * (1.0 - t / 0.25))
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
                }

                // No .blendMode — overlapping alpha-pre-mult ellipses
                // already composite the way we want on the dark backdrop.
                Canvas { ctx, _ in
                    for burst in bursts {
                        let t = elapsed - burst.launchTime
                        guard t > 0 else { continue }

                        if t < riseTime {
                            drawRisingShell(ctx: ctx, burst: burst, t: t)
                        } else {
                            drawExplosion(ctx: ctx, burst: burst, t: t)
                        }
                    }
                }
            }
            .onChange(of: elapsed) { _, now in
                // Fire the pew on the first frame past detonation.
                for (i, burst) in bursts.enumerated() {
                    let detonationAt = burst.launchTime + riseTime
                    if now >= detonationAt && !poppedIndices.contains(i) {
                        poppedIndices.insert(i)
                        FireworksSounds.pew(frequency: burst.pewFrequency)
                    }
                }
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .ignoresSafeArea()
    }

    private func drawRisingShell(ctx: GraphicsContext, burst: Burst, t: TimeInterval) {
        let progress = t / riseTime
        let easeOut = 1 - (1 - progress) * (1 - progress)
        let y = bounds.height - (bounds.height - burst.peakY) * CGFloat(easeOut)
        let trailLength: CGFloat = 22
        let path = Path { p in
            p.move(to: CGPoint(x: burst.startX, y: y))
            p.addLine(to: CGPoint(x: burst.startX, y: y + trailLength))
        }
        var c = ctx
        c.opacity = 0.9
        c.stroke(path, with: .color(burst.color), lineWidth: 3)
        // Hot tip + glow halo.
        let headRect = CGRect(x: burst.startX - 3, y: y - 3, width: 6, height: 6)
        c.fill(Path(ellipseIn: headRect), with: .color(.white))
        let halo = CGRect(x: burst.startX - 10, y: y - 10, width: 20, height: 20)
        var haloCtx = ctx
        haloCtx.opacity = 0.35
        haloCtx.fill(Path(ellipseIn: halo), with: .color(burst.color))
    }

    /// Detonation: flash, main sparks, twinkles, optional secondaries.
    private func drawExplosion(ctx: GraphicsContext, burst: Burst, t: TimeInterval) {
        let dt = t - riseTime
        guard dt < sparkLifetime else { return }
        let fade = 1.0 - dt / sparkLifetime
        let origin = CGPoint(x: burst.startX, y: burst.peakY)

        // 220ms flash + persistent halo so the burst reads as
        // "lit from within" rather than scattered dots after 0.2s.
        if dt < 0.22 {
            let flashAlpha = (0.22 - dt) / 0.22
            let radius = CGFloat(70 + dt * 360)
            let rect = CGRect(
                x: burst.startX - radius,
                y: burst.peakY - radius,
                width: radius * 2,
                height: radius * 2
            )
            var haloCtx = ctx
            haloCtx.opacity = flashAlpha * 0.55
            haloCtx.fill(Path(ellipseIn: rect), with: .color(burst.color))
            var coreCtx = ctx
            coreCtx.opacity = flashAlpha * 0.9
            let coreR = radius * 0.4
            let coreRect = CGRect(
                x: burst.startX - coreR,
                y: burst.peakY - coreR,
                width: coreR * 2,
                height: coreR * 2
            )
            coreCtx.fill(Path(ellipseIn: coreRect), with: .color(.white))
        }
        // Persistent halo so the colored glow stays with the sparks.
        let lingerRadius = CGFloat(120 + dt * 60)
        let lingerRect = CGRect(
            x: burst.startX - lingerRadius,
            y: burst.peakY - lingerRadius,
            width: lingerRadius * 2,
            height: lingerRadius * 2
        )
        var lingerCtx = ctx
        lingerCtx.opacity = fade * 0.18
        lingerCtx.fill(Path(ellipseIn: lingerRect), with: .color(burst.color))

        // Trail sampled at 3 prior offsets for a comet streak.
        let mainRadius: CGFloat = 3.6
        let trailSegments: [TimeInterval] = [0.04, 0.09, 0.14]
        for spark in burst.sparks {
            let pos = sparkPosition(spark: spark, origin: origin, dt: dt)

            let twinkle = 0.65 + 0.35 * sin(dt * 18 + spark.twinkle)
            var c = ctx
            c.opacity = fade * twinkle

            // Each segment dimmer + thinner than the last.
            var prevPoint = pos
            for (idx, offset) in trailSegments.enumerated() {
                let prevDt = max(0, dt - offset)
                let segPoint = sparkPosition(spark: spark, origin: origin, dt: prevDt)
                let segOpacity = fade * twinkle * (1.0 - Double(idx) * 0.28)
                let segWidth = mainRadius * (1.0 - CGFloat(idx) * 0.22)
                var segCtx = ctx
                segCtx.opacity = max(0, segOpacity)
                let path = Path { p in
                    p.move(to: prevPoint)
                    p.addLine(to: segPoint)
                }
                segCtx.stroke(path, with: .color(burst.color), lineWidth: segWidth)
                prevPoint = segPoint
            }

            c.fill(
                Path(ellipseIn: CGRect(x: pos.x - mainRadius, y: pos.y - mainRadius, width: mainRadius * 2, height: mainRadius * 2)),
                with: .color(burst.color)
            )
            // White hot-spot core so heads pop.
            let coreR = mainRadius * 0.5
            var coreCtx = ctx
            coreCtx.opacity = fade * twinkle * 0.9
            coreCtx.fill(
                Path(ellipseIn: CGRect(x: pos.x - coreR, y: pos.y - coreR, width: coreR * 2, height: coreR * 2)),
                with: .color(.white)
            )
        }

        // Glitter sparks within the burst.
        if dt < twinkleLifetime {
            let tFade = 1.0 - dt / twinkleLifetime
            let twR: CGFloat = 2.2
            for spark in burst.twinkles {
                let pos = sparkPosition(spark: spark, origin: origin, dt: dt)
                let blink = 0.4 + 0.6 * sin(dt * 36 + spark.twinkle)
                var c = ctx
                c.opacity = tFade * max(0, blink)
                c.fill(
                    Path(ellipseIn: CGRect(x: pos.x - twR, y: pos.y - twR, width: twR * 2, height: twR * 2)),
                    with: .color(.white)
                )
            }
        }

        for sec in burst.secondaries {
            let secDt = dt - sec.delay
            guard secDt > 0, secDt < sparkLifetime * 0.7 else { continue }
            let secFade = 1.0 - secDt / (sparkLifetime * 0.7)
            let radius: CGFloat = 2.0
            let origin = CGPoint(x: burst.startX + sec.offset.x, y: burst.peakY + sec.offset.y)
            for spark in sec.sparks {
                let pos = sparkPosition(spark: spark, origin: origin, dt: secDt)
                var c = ctx
                c.opacity = secFade * 0.85
                c.fill(
                    Path(ellipseIn: CGRect(x: pos.x - radius, y: pos.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(sec.color)
                )
            }
        }
    }

    private func sparkPosition(spark: Spark, origin: CGPoint, dt: TimeInterval) -> CGPoint {
        // Pure ballistic — outward velocity plus gravity. A drag profile
        // pulled sparks back toward the center ("sucked into a black hole").
        let x = origin.x + spark.vx * CGFloat(dt)
        let y = origin.y + spark.vy * CGFloat(dt)
              + 0.5 * sparkGravity * CGFloat(dt * dt)
        return CGPoint(x: x, y: y)
    }
}

/// Synthesized "pew" pool. AVAudioPlayer only plays one sound at a time;
/// a small ring buffer per frequency keeps overlapping bursts from
/// cutting each other off and avoids per-pew construction cost.
@MainActor
private enum FireworksSounds {
    private static var pool: [Double: [AVAudioPlayer]] = [:]
    private static let poolSize = 3

    static func pew(frequency: Double) {
        guard let player = nextPlayer(for: frequency) else { return }
        player.stop()
        player.currentTime = 0
        player.play()
    }

    private static func nextPlayer(for frequency: Double) -> AVAudioPlayer? {
        if let players = pool[frequency] {
            // Round-robin: pick the most-likely-idle player.
            return players.min(by: { ($0.isPlaying ? 1 : 0, $0.currentTime) < ($1.isPlaying ? 1 : 0, $1.currentTime) })
        }
        let data = makePewWave(frequency: frequency)
        var players: [AVAudioPlayer] = []
        for _ in 0..<poolSize {
            if let p = try? AVAudioPlayer(data: data) {
                p.volume = 0.25
                p.prepareToPlay()
                players.append(p)
            }
        }
        pool[frequency] = players
        return players.first
    }

    /// ~0.22s: fast downward freq sweep, sharp attack, exponential decay.
    private static func makePewWave(frequency: Double) -> Data {
        let sampleRate: Double = 44100
        let duration: Double = 0.22
        let numSamples = Int(duration * sampleRate)
        let amplitude = Double(Int16.max) * 0.55

        var samples = [Int16]()
        samples.reserveCapacity(numSamples)
        var phase: Double = 0
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            // Falls from `frequency` to ~30%.
            let freq = frequency * (1.0 - 0.7 * (t / duration))
            phase += 2 * .pi * freq / sampleRate
            // Sine + a touch of square for punch.
            let sine = sin(phase)
            let square = sine > 0 ? 1.0 : -1.0
            let mixed = sine * 0.7 + square * 0.3
            // ~5ms fade-in to avoid the click.
            let attack = min(1.0, t / 0.005)
            let decay = exp(-t * 14)
            samples.append(Int16(amplitude * mixed * attack * decay))
        }

        let dataSize = samples.count * MemoryLayout<Int16>.size
        var data = Data()
        func writeUInt32LE(_ value: UInt32) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func writeUInt16LE(_ value: UInt16) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        writeUInt32LE(UInt32(36 + dataSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        writeUInt32LE(16)
        writeUInt16LE(1)
        writeUInt16LE(1)
        writeUInt32LE(UInt32(sampleRate))
        writeUInt32LE(UInt32(sampleRate) * 2)
        writeUInt16LE(2)
        writeUInt16LE(16)
        data.append(contentsOf: "data".utf8)
        writeUInt32LE(UInt32(dataSize))
        samples.withUnsafeBufferPointer { ptr in
            data.append(UnsafeBufferPointer(
                start: UnsafeRawPointer(ptr.baseAddress!).assumingMemoryBound(to: UInt8.self),
                count: dataSize
            ))
        }
        return data
    }
}
