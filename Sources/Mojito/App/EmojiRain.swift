import AppKit
import SwiftUI

/// One of the discoverable effects. See `EasterEgg` for the
/// (opaque) identity; the trigger keyword is decoded at runtime from
/// `EggStrings` and not present in source.
@MainActor
enum EmojiRain {
    private static var activeWindow: NSWindow?

    /// Acceleration in screen-pixels per second². Tuned so most particles
    /// reach the bottom within ~1 second of launching — feels like real
    /// gravity, not a slow fall.
    private static let gravity: CGFloat = 1800

    /// Spawn the rain. Re-trigger replaces any in-flight rain instead of being suppressed.
    static func start(emitFor emit: TimeInterval = 1.5, particleLifetime: TimeInterval = 4.0) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        activeWindow?.orderOut(nil)
        activeWindow = nil

        // Pull random emoji from the full database. With ~1900 entries, most
        // particles end up unique; that's fine — we dedupe before resolving
        // Text glyphs each frame.
        let pool = EmojiDatabase.shared.all
        guard !pool.isEmpty else { return }

        let particlesPerSecond = 45
        let total = Int(Double(particlesPerSecond) * emit)
        let particles: [Particle] = (0..<total).map { _ in
            Particle(
                emoji: pool.randomElement()?.character ?? "🎉",
                startX: .random(in: 0...frame.width),
                vx: .random(in: -50...50),
                vy: .random(in: 60...140),
                spin: .random(in: -2.5...2.5),
                scale: .random(in: 0.75...1.25),
                launchTime: .random(in: 0..<emit),
                lifetime: particleLifetime,
                // Lower damping = mushier landings. Particles bounce a short
                // distance then fall off, instead of pinging back near the top.
                bounceDamping: .random(in: 0.20...0.40)
            )
        }

        let panel = ParticlePanel.makeFullScreen(frame: frame)
        let host = NSHostingView(rootView: RainView(
            particles: particles,
            startDate: Date(),
            bounds: frame.size,
            gravity: gravity
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

        let totalDuration = emit + particleLifetime + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            MainActor.assumeIsolated { dismiss() }
        }
    }
}

/// One falling emoji.
private struct Particle {
    let emoji: String
    let startX: CGFloat
    let vx: CGFloat
    let vy: CGFloat
    let spin: Double
    let scale: CGFloat
    let launchTime: TimeInterval
    let lifetime: TimeInterval
    /// Energy retained after the single bounce. 1.0 = perfect bounce; 0 = no bounce.
    let bounceDamping: CGFloat
}

private struct RainView: View {
    let particles: [Particle]
    let startDate: Date
    let bounds: CGSize
    let gravity: CGFloat

    private let baseSize: CGFloat = 34

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            Canvas { ctx, _ in
                // Resolve once per unique emoji per frame, reuse across all
                // particles of that emoji.
                let uniqueEmojis = Set(particles.map(\.emoji))
                var resolved: [String: GraphicsContext.ResolvedText] = [:]
                resolved.reserveCapacity(uniqueEmojis.count)
                for emoji in uniqueEmojis {
                    resolved[emoji] = ctx.resolve(Text(emoji).font(.system(size: baseSize)))
                }

                // Bounce against the actual bottom of the screen.
                let groundY = bounds.height
                let offScreenY = bounds.height + baseSize * 2

                for p in particles {
                    let t = elapsed - p.launchTime
                    guard t > 0, t < p.lifetime else { continue }

                    let x = p.startX + p.vx * t
                    let y = positionY(for: p, t: t, groundY: groundY)

                    guard y < offScreenY else { continue }

                    // Linear fade-out over the last 30% of lifetime.
                    let fadeStart = p.lifetime * 0.7
                    let fade: Double
                    if t < fadeStart {
                        fade = 1.0
                    } else {
                        fade = max(0.0, 1.0 - (t - fadeStart) / (p.lifetime - fadeStart))
                    }

                    var c = ctx
                    c.opacity = fade
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.spin * t))
                    c.scaleBy(x: p.scale, y: p.scale)
                    if let r = resolved[p.emoji] {
                        c.draw(r, at: .zero, anchor: .center)
                    }
                }
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .ignoresSafeArea()
    }

    /// Closed-form position with one bounce. Pre-bounce uses standard
    /// kinematics; we solve for `t_bounce` (when the trajectory first hits
    /// `groundY`) as a quadratic, then reflect velocity by `bounceDamping`
    /// and recompute from there.
    private func positionY(for p: Particle, t: TimeInterval, groundY: CGFloat) -> CGFloat {
        let y0 = -baseSize - 10
        let yFirst = y0 + p.vy * t + 0.5 * gravity * t * t

        // Phase 1 — still in the first fall.
        if yFirst < groundY {
            return yFirst
        }

        // Phase 2 — bounce time is the positive root of:
        //   ½g·t² + vy·t + (y₀ - groundY) = 0
        let a = 0.5 * gravity
        let b = p.vy
        let c = y0 - groundY
        let disc = b * b - 4 * a * c
        guard disc >= 0 else { return yFirst }
        let tBounce = (-b + sqrt(disc)) / (2 * a)

        let vAtImpact = p.vy + gravity * tBounce
        let vAfterBounce = -vAtImpact * p.bounceDamping
        let tAfter = t - tBounce

        return groundY + vAfterBounce * tAfter + 0.5 * gravity * tAfter * tAfter
    }
}
