import AppKit
import SwiftUI

/// Drifting snowflakes. Slower terminal velocity than EmojiRain,
/// per-particle sine drift, no bounce. Dismiss MUST null `contentView`
/// to stop the TimelineView frame ticker.
@MainActor
enum Snowfall {
    private static var activeWindow: NSWindow?

    static func start(emitFor emit: TimeInterval = 8.0, particleLifetime: TimeInterval = 11.0) {
        guard let frame = ParticlePanel.primaryScreenFrame() else { return }

        activeWindow?.orderOut(nil)
        activeWindow = nil

        // Low budget so a 32" retina keeps up.
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
                // Drop the tree so TimelineView stops driving frames —
                // otherwise it animates off-screen and pegs the GPU.
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
                // Resolve ONCE per body, not per particle.
                let resolvedSharp = ctx.resolve(
                    Text(verbatim: "❅").font(.system(size: 24)).foregroundColor(.white)
                )
                let resolvedRound = ctx.resolve(
                    Text(verbatim: "❆").font(.system(size: 24)).foregroundColor(.white)
                )
                for (i, f) in flakes.enumerated() {
                    let t = elapsed - f.launchTime
                    guard t > 0, t < lifetime else { continue }
                    let y = -30 + f.fallSpeed * CGFloat(t)
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
