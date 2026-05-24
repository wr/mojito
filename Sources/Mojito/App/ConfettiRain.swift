import AppKit
import SwiftUI

/// Full-screen confetti shower. Triggered by the the keyword easter egg.
///
/// Similar architecture to EmojiRain (transparent click-through panel, Canvas
/// inside TimelineView, closed-form physics) but the particles are tilted
/// colored rectangles instead of emoji. Cheaper to draw, and a cleaner
/// "celebration" read than mixed emoji.
@MainActor
enum ConfettiRain {
    private static var activeWindow: NSWindow?
    private static let gravity: CGFloat = 1500

    static func start(emitFor emit: TimeInterval = 0.7, particleLifetime: TimeInterval = 3.5) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        // Re-trigger replaces any in-flight shower instead of being suppressed.
        activeWindow?.orderOut(nil)
        activeWindow = nil

        let colors: [Color] = [
            .red, .orange, .yellow, .green, .mint, .teal,
            .cyan, .blue, .indigo, .purple, .pink
        ]

        // Two cannons: bottom-left and bottom-right. Each fires particles up
        // and inward across most of the screen width, then gravity pulls
        // them back down. Initial vy is strongly negative (upward); vx is
        // signed by emitter side with some spread.
        let particlesPerSide = Int(Double(60) * emit)
        let cannonY = frame.height + 10           // just below the bottom edge
        let leftCannonX = -10.0                   // just left of the left edge
        let rightCannonX = Double(frame.width) + 10
        var particles: [Particle] = []
        particles.reserveCapacity(particlesPerSide * 2)

        for side in [-1.0, 1.0] {                 // -1 = left cannon, +1 = right
            let originX = side < 0 ? leftCannonX : rightCannonX
            for _ in 0..<particlesPerSide {
                // Bias horizontal velocity toward the screen center.
                let vxMagnitude: CGFloat = .random(in: 700...1100)
                let vx = side < 0 ? vxMagnitude : -vxMagnitude
                particles.append(Particle(
                    color: colors.randomElement() ?? .pink,
                    startX: CGFloat(originX) + .random(in: -8...8),
                    startY: CGFloat(cannonY) + .random(in: -8...8),
                    vx: vx + .random(in: -150...150),
                    vy: -.random(in: 900...1400),
                    spin: .random(in: -8.0...8.0),
                    width: .random(in: 6...10),
                    height: .random(in: 10...16),
                    rotation: .random(in: 0...(.pi * 2)),
                    launchTime: .random(in: 0..<emit),
                    lifetime: particleLifetime
                ))
            }
        }

        let panel = ParticlePanel.makeFullScreen(frame: frame)
        let host = NSHostingView(rootView: ConfettiView(
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

private struct Particle {
    let color: Color
    let startX: CGFloat
    let startY: CGFloat
    let vx: CGFloat
    let vy: CGFloat
    let spin: Double
    let width: CGFloat
    let height: CGFloat
    let rotation: Double
    let launchTime: TimeInterval
    let lifetime: TimeInterval
}

private struct ConfettiView: View {
    let particles: [Particle]
    let startDate: Date
    let bounds: CGSize
    let gravity: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            Canvas { ctx, _ in
                let offScreenY = bounds.height + 30
                for p in particles {
                    let t = elapsed - p.launchTime
                    guard t > 0, t < p.lifetime else { continue }

                    let x = p.startX + p.vx * t
                    let y = p.startY + p.vy * t + 0.5 * gravity * t * t
                    // Particles travel off the top, sides, OR back down past
                    // the bottom — skip when out of bounds in any direction.
                    guard y < offScreenY,
                          x > -30, x < bounds.width + 30 else { continue }

                    let fadeStart = p.lifetime * 0.75
                    let fade: Double = t < fadeStart
                        ? 1.0
                        : max(0.0, 1.0 - (t - fadeStart) / (p.lifetime - fadeStart))

                    var c = ctx
                    c.opacity = fade
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.rotation + p.spin * t))
                    let rect = CGRect(x: -p.width / 2, y: -p.height / 2, width: p.width, height: p.height)
                    c.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(p.color))
                }
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .ignoresSafeArea()
    }
}
