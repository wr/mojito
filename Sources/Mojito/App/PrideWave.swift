import AppKit
import SwiftUI

/// Centered rainbow ribbon that ripples across the screen. Triggered by the
/// the keyword easter egg.
///
/// All six pride-flag stripes share a single waveform — the bottom of stripe i
/// is the top of stripe i+1, so adjacent colors meet on a perfect shared edge
/// with no gaps or overlap. Translucent so the user can still see through to
/// whatever they were doing.
@MainActor
enum PrideWave {
    private static var activeWindow: NSWindow?

    static func start(duration: TimeInterval = 3.5) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        // Re-trigger replaces any in-flight wave instead of being suppressed.
        activeWindow?.orderOut(nil)
        activeWindow = nil

        let panel = ParticlePanel.makeFullScreen(frame: frame)
        let host = NSHostingView(rootView: PrideWaveView(
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

private struct PrideWaveView: View {
    let startDate: Date
    let bounds: CGSize
    let duration: TimeInterval

    // Six-stripe flag, top → bottom.
    private let stripes: [Color] = [
        Color(red: 0.89, green: 0.13, blue: 0.13),
        Color(red: 1.00, green: 0.55, blue: 0.00),
        Color(red: 1.00, green: 0.92, blue: 0.23),
        Color(red: 0.00, green: 0.55, blue: 0.18),
        Color(red: 0.00, green: 0.32, blue: 0.85),
        Color(red: 0.46, green: 0.13, blue: 0.62),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            Canvas { ctx, _ in
                drawBand(ctx: ctx, t: elapsed)
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .ignoresSafeArea()
    }

    private func drawBand(ctx: GraphicsContext, t: TimeInterval) {
        // Band is ~1/3 of screen height, centered vertically. Bigger screens
        // get a slightly taller band, capped so it doesn't dwarf laptops.
        let stripeHeight: CGFloat = max(60, min(110, bounds.height / 18))
        let bandHeight = stripeHeight * CGFloat(stripes.count)
        let bandTopBase = (bounds.height - bandHeight) / 2

        // Wave parameters. Amplitude is a fraction of the band height so the
        // ripple is proportional to the band — never larger than a stripe.
        let waveAmp: CGFloat = min(stripeHeight * 0.55, 38)
        let waveLen: CGFloat = max(280, bounds.width / 2.4)
        let phase = t * 1.8

        // Fade in over the first 0.4s, fade out over the last 0.5s.
        let fade: Double
        if t < 0.4 {
            fade = t / 0.4
        } else if t > duration - 0.5 {
            fade = max(0.0, (duration - t) / 0.5)
        } else {
            fade = 1.0
        }

        let step: CGFloat = 10
        for (i, color) in stripes.enumerated() {
            let topBase = bandTopBase + CGFloat(i) * stripeHeight
            let botBase = bandTopBase + CGFloat(i + 1) * stripeHeight

            var path = Path()
            var x: CGFloat = -30
            path.move(to: CGPoint(x: x, y: topBase + wave(at: x, len: waveLen, amp: waveAmp, phase: phase)))
            while x <= bounds.width + 30 {
                path.addLine(to: CGPoint(x: x, y: topBase + wave(at: x, len: waveLen, amp: waveAmp, phase: phase)))
                x += step
            }
            x = bounds.width + 30
            while x >= -30 {
                path.addLine(to: CGPoint(x: x, y: botBase + wave(at: x, len: waveLen, amp: waveAmp, phase: phase)))
                x -= step
            }
            path.closeSubpath()

            var c = ctx
            // Slight translucency so the underlying screen still reads through.
            c.opacity = fade * 0.92
            c.fill(path, with: .color(color))
        }
    }

    private func wave(at x: CGFloat, len: CGFloat, amp: CGFloat, phase: Double) -> CGFloat {
        amp * CGFloat(sin(2.0 * .pi * Double(x) / Double(len) + phase))
    }
}
