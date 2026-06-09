import AppKit
import SwiftUI

/// "+30 LIVES" Contra-cheat banner. Triggered by the state machine when
/// ↑↑↓↓←→←→BA is matched in `.capturing` empty-query state.
@MainActor
enum KonamiPayoff {
    private static var activeWindow: NSWindow?

    static func start(duration: TimeInterval = 3.5) {
        guard let frame = ParticlePanel.primaryScreenFrame() else { return }

        activeWindow?.orderOut(nil)
        activeWindow = nil

        let panel = ParticlePanel.makeFullScreen(frame: frame)
        let host = NSHostingView(rootView: KonamiPayoffView(
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
                panel.contentView = nil
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

private struct KonamiPayoffView: View {
    let startDate: Date
    let bounds: CGSize
    let duration: TimeInterval

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let fadeIn = min(1.0, elapsed / 0.25)
            let fadeOut = elapsed > duration - 0.6
                ? max(0.0, (duration - elapsed) / 0.6)
                : 1.0
            let alpha = fadeIn * fadeOut

            ZStack {
                Canvas { ctx, _ in
                    let title = Text(verbatim: "+30 LIVES")
                        .font(.system(size: 96, weight: .black, design: .monospaced))
                        .foregroundColor(.yellow)
                    let resolved = ctx.resolve(title)
                    let size = resolved.measure(in: bounds)
                    var c = ctx
                    c.opacity = alpha
                    c.draw(resolved, at: CGPoint(
                        x: bounds.width / 2 - size.width / 2,
                        y: bounds.height / 2 - size.height / 2
                    ))

                    let sub = Text(verbatim: "↑ ↑ ↓ ↓ ← → ← → B A")
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    let rSub = ctx.resolve(sub)
                    let subSize = rSub.measure(in: bounds)
                    c.draw(rSub, at: CGPoint(
                        x: bounds.width / 2 - subSize.width / 2,
                        y: bounds.height / 2 + 60
                    ))
                }
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .ignoresSafeArea()
    }
}
