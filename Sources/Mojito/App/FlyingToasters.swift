import AppKit
import SwiftUI

/// After Dark's iconic Flying Toasters. Triggered by `:toasters:`.
///
/// A flock of winged toasters glides diagonally across the screen (top-right
/// to bottom-left), with the occasional slice of toast for variety. Wings flap
/// at ~6 Hz. Each item launches at a random time and position so the screen
/// stays populated for the duration.
@MainActor
enum FlyingToasters {
    private static var activeWindow: NSWindow?

    static func start(duration: TimeInterval = 8.0) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        activeWindow?.orderOut(nil)
        activeWindow = nil

        let itemCount = 14
        var items: [Toaster] = []
        items.reserveCapacity(itemCount)
        for _ in 0..<itemCount {
            // Start above and to the right of visible bounds; travel down-left.
            let startX = CGFloat.random(in: frame.width * 0.3...frame.width * 1.4)
            let startY = CGFloat.random(in: -frame.height * 0.4...frame.height * 0.4)
            items.append(Toaster(
                isToast: Double.random(in: 0...1) < 0.25,
                startX: startX,
                startY: startY,
                speed: .random(in: 80...160),
                launchTime: .random(in: 0..<(duration * 0.6)),
                wingPhaseOffset: .random(in: 0...(2 * .pi))
            ))
        }

        let panel = ParticlePanel.makeFullScreen(frame: frame)
        let host = NSHostingView(rootView: ToastersView(
            items: items,
            startDate: Date(),
            bounds: frame.size,
            duration: duration
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

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.3) {
            MainActor.assumeIsolated { dismiss() }
        }
    }
}

private struct Toaster {
    let isToast: Bool
    let startX: CGFloat
    let startY: CGFloat
    let speed: CGFloat
    let launchTime: TimeInterval
    let wingPhaseOffset: Double
}

private struct ToastersView: View {
    let items: [Toaster]
    let startDate: Date
    let bounds: CGSize
    let duration: TimeInterval

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            Canvas { ctx, _ in
                let endFade = elapsed > duration - 0.5
                    ? max(0.0, (duration - elapsed) / 0.5)
                    : 1.0

                for item in items {
                    let t = elapsed - item.launchTime
                    guard t > 0 else { continue }
                    // Direction: down-left at ~30° below horizontal.
                    let angle = Double.pi / 6
                    let dx = -CGFloat(cos(angle)) * item.speed * CGFloat(t)
                    let dy = CGFloat(sin(angle)) * item.speed * CGFloat(t)
                    let x = item.startX + dx
                    let y = item.startY + dy

                    // Skip when fully off bottom-left.
                    guard x > -120, y < bounds.height + 120 else { continue }

                    let wingPhase = elapsed * 12 + item.wingPhaseOffset

                    var c = ctx
                    c.opacity = endFade
                    if item.isToast {
                        drawToast(ctx: c, center: CGPoint(x: x, y: y))
                    } else {
                        drawToaster(ctx: c, center: CGPoint(x: x, y: y), wingPhase: wingPhase)
                    }
                }
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .ignoresSafeArea()
        .background(Color.black.opacity(0.7))
    }

    private func drawToaster(ctx: GraphicsContext, center: CGPoint, wingPhase: Double) {
        let bodyRect = CGRect(x: center.x - 32, y: center.y - 22, width: 64, height: 44)
        // Chrome body.
        ctx.fill(
            Path(roundedRect: bodyRect, cornerRadius: 6),
            with: .linearGradient(
                Gradient(colors: [Color(white: 0.9), Color(white: 0.55), Color(white: 0.85)]),
                startPoint: CGPoint(x: bodyRect.minX, y: bodyRect.minY),
                endPoint: CGPoint(x: bodyRect.minX, y: bodyRect.maxY)
            )
        )
        // Toast slots.
        let slotRect = CGRect(x: bodyRect.minX + 8, y: bodyRect.minY + 6, width: bodyRect.width - 16, height: 8)
        ctx.fill(Path(roundedRect: slotRect, cornerRadius: 2), with: .color(.black))
        // Lever knob.
        ctx.fill(
            Path(roundedRect: CGRect(x: bodyRect.maxX - 9, y: bodyRect.midY - 3, width: 7, height: 6), cornerRadius: 1),
            with: .color(Color(white: 0.3))
        )

        // Wings — two trapezoids, flap up/down with phase.
        let flap = CGFloat(sin(wingPhase)) * 10
        let wingTopY = center.y - 8 - flap
        var wingPath = Path()
        // Left wing.
        wingPath.move(to: CGPoint(x: bodyRect.minX + 4, y: bodyRect.minY + 8))
        wingPath.addLine(to: CGPoint(x: bodyRect.minX - 28, y: wingTopY - 6))
        wingPath.addLine(to: CGPoint(x: bodyRect.minX - 24, y: wingTopY + 6))
        wingPath.addLine(to: CGPoint(x: bodyRect.minX + 4, y: bodyRect.minY + 16))
        wingPath.closeSubpath()
        // Right wing.
        wingPath.move(to: CGPoint(x: bodyRect.maxX - 4, y: bodyRect.minY + 8))
        wingPath.addLine(to: CGPoint(x: bodyRect.maxX + 28, y: wingTopY - 6))
        wingPath.addLine(to: CGPoint(x: bodyRect.maxX + 24, y: wingTopY + 6))
        wingPath.addLine(to: CGPoint(x: bodyRect.maxX - 4, y: bodyRect.minY + 16))
        wingPath.closeSubpath()
        ctx.fill(wingPath, with: .color(Color(white: 0.95)))
        ctx.stroke(wingPath, with: .color(.black), lineWidth: 1)
    }

    private func drawToast(ctx: GraphicsContext, center: CGPoint) {
        // Slice of toast: rounded golden-brown rectangle with darker crust.
        let outer = CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44)
        ctx.fill(
            Path(roundedRect: outer, cornerRadius: 4),
            with: .color(Color(red: 0.7, green: 0.45, blue: 0.18))
        )
        let inner = outer.insetBy(dx: 4, dy: 4)
        ctx.fill(
            Path(roundedRect: inner, cornerRadius: 3),
            with: .color(Color(red: 0.96, green: 0.78, blue: 0.42))
        )
    }
}
