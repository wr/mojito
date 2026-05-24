import AppKit
import SwiftUI

/// Drifting snowflakes. Triggered by the keyword.
///
/// Reuses ParticlePanel + Canvas + TimelineView. Slower terminal velocity than
/// EmojiRain, sideways drift via per-particle sine wave, no bounce.
///
/// Performance / leak fixes (WEL-13/43):
///   - On dismiss we set `panel.contentView = nil` so the SwiftUI tree (and
///     its TimelineView frame ticker) actually tears down. Without this the
///     TimelineView keeps requesting redraws forever, even though
///     `paused: false` is documented as "always animate" — `orderOut` alone
///     doesn't stop it. Same pattern as BouncingDVD.
///   - `ctx.resolve(Text(...))` happens once per Canvas body invocation,
///     hoisted out of the per-particle loop. Previously we paid for 640+
///     resolves every frame.
///   - Particle count reduced from 80/sec to 50/sec (was 640 total; now 400).
@MainActor
enum Snowfall {
    private static var activeWindow: NSWindow?

    static func start(emitFor emit: TimeInterval = 8.0, particleLifetime: TimeInterval = 11.0) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        activeWindow?.orderOut(nil)
        activeWindow = nil

        // Particle budget — kept low so even a 32-inch retina can keep up.
        // 20/sec × 8s emit = 160 total particles, ~5–6× cheaper than the
        // prior 50/sec setting that was still dropping frames.
        let particlesPerSecond = 20
        let total = Int(Double(particlesPerSecond) * emit)
        let flakes: [Flake] = (0..<total).map { _ in
            Flake(
                startX: .random(in: -40...frame.width + 40),
                fallSpeed: .random(in: 45...140),
                driftAmplitude: .random(in: 18...52),
                driftFrequency: .random(in: 0.4...1.2),
                phase: .random(in: 0...(2 * .pi)),
                size: .random(in: 9...26),
                opacity: .random(in: 0.65...1.0),
                launchTime: .random(in: 0..<emit),
                rotationRate: .random(in: -0.6...0.6),
                rotationPhase: .random(in: 0...(2 * .pi))
            )
        }

        let panel = ParticlePanel.makeFullScreen(frame: frame)
        let host = NSHostingView(rootView: SnowfallView(
            flakes: flakes,
            startDate: Date(),
            bounds: frame.size,
            lifetime: particleLifetime
        ))
        host.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = host
        panel.orderFrontRegardless()
        activeWindow = panel

        var cancelToken: (() -> Void)?
        let dismiss = {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                // Drop the SwiftUI tree so TimelineView stops driving frames.
                // Without this the snowfall keeps animating off-screen and
                // pegs the GPU until Mojito quits.
                panel.contentView = nil
                cancelToken?(); cancelToken = nil
                if activeWindow === panel { activeWindow = nil }
            }
        }
        cancelToken = EffectDismisser.register(dismiss)

        let totalDuration = emit + particleLifetime + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            MainActor.assumeIsolated { dismiss() }
        }
    }
}

private struct Flake {
    let startX: CGFloat
    let fallSpeed: CGFloat
    let driftAmplitude: CGFloat
    let driftFrequency: Double
    let phase: Double
    let size: CGFloat
    let opacity: Double
    let launchTime: TimeInterval
    /// Radians per second. Signed so half the flakes spin clockwise.
    let rotationRate: Double
    /// Initial rotation offset so flakes don't all start at 0°.
    let rotationPhase: Double
}

private struct SnowfallView: View {
    let flakes: [Flake]
    let startDate: Date
    let bounds: CGSize
    let lifetime: TimeInterval

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            Canvas { ctx, _ in
                // Resolve the two glyph variants ONCE per body invocation.
                // The previous code resolved inside the per-particle loop —
                // 640 redundant Text resolutions every frame.
                let resolvedSharp = ctx.resolve(
                    Text("❅").font(.system(size: 24)).foregroundColor(.white)
                )
                let resolvedRound = ctx.resolve(
                    Text("❆").font(.system(size: 24)).foregroundColor(.white)
                )
                for (i, f) in flakes.enumerated() {
                    let t = elapsed - f.launchTime
                    guard t > 0, t < lifetime else { continue }
                    let y = -30 + f.fallSpeed * CGFloat(t)
                    // Cheap on-screen culling so we skip translate/rotate/draw
                    // for particles that aren't visible yet or have fallen
                    // off the bottom.
                    guard y > -30, y < bounds.height + 30 else { continue }
                    let dx = f.driftAmplitude * CGFloat(sin(f.driftFrequency * t + f.phase))
                    let x = f.startX + dx

                    let fadeIn: Double = min(1.0, t / 0.4)
                    let fadeOut: Double = t > lifetime - 0.8
                        ? max(0.0, (lifetime - t) / 0.8)
                        : 1.0

                    var c = ctx
                    c.opacity = f.opacity * fadeIn * fadeOut
                    c.translateBy(x: x, y: y)
                    let scale = f.size / 24.0
                    c.scaleBy(x: scale, y: scale)
                    c.rotate(by: .radians(f.rotationPhase + f.rotationRate * t))
                    c.draw(i % 2 == 0 ? resolvedSharp : resolvedRound, at: .zero, anchor: .center)
                }
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .ignoresSafeArea()
    }
}
