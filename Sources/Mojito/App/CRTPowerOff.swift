import AppKit
import SwiftUI

/// One of the discoverable effects. See `EasterEgg` for the
/// (opaque) identity; the trigger keyword is decoded at runtime from
/// `EggStrings` and not present in source.
@MainActor
enum CRTPowerOff {
    private static var activeWindow: NSWindow?
    private static var player: NSSound?

    static func start() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        activeWindow?.orderOut(nil)
        activeWindow = nil
        player?.stop()
        player = nil

        // Note: this overlay accepts clicks (so user can dismiss by clicking),
        // unlike a click-through ParticlePanel. Use a normal borderless panel.
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        var cancelToken: (() -> Void)?
        let dismiss = {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                player?.stop()
                player = nil
                cancelToken?(); cancelToken = nil
                if activeWindow === panel { activeWindow = nil }
            }
        }

        let host = NSHostingView(rootView: CRTPowerOffView(
            startDate: Date(),
            bounds: frame.size,
            onTap: dismiss
        ))
        host.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = host
        panel.orderFrontRegardless()
        activeWindow = panel

        // Play the thunk instantly — no async delay. Trim any leading
        // silence in the WAV at the asset level if there's still latency.
        if let sound = AudioBlob.load("s13") {
            player = sound
            sound.volume = 0.8 // 20% quieter than the default 1.0
            sound.play()
        }

        cancelToken = EffectDismisser.register(dismiss)

        // Total animation budget ~1.2s, plus brief hold on black.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            MainActor.assumeIsolated { dismiss() }
        }
    }
}

private struct CRTPowerOffView: View {
    let startDate: Date
    let bounds: CGSize
    let onTap: () -> Void

    /// Animation breakpoints (seconds).
    private let phase1End: TimeInterval = 0.15  // vertical collapse
    private let phase2End: TimeInterval = 0.35  // horizontal collapse to dot
    private let phase3End: TimeInterval = 1.2   // dot fades

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            ZStack {
                // The "frame" goes solid black almost instantly so the
                // collapsing white shape reads as the picture imploding.
                Color.black.opacity(min(1.0, elapsed / 0.06))

                let shape = currentShape(elapsed: elapsed)
                if shape.opacity > 0.01 {
                    // Layered phosphor glow: a soft cyan outer halo plus a
                    // tight white inner core. Reads more like real CRT
                    // discharge than a single hard shadow.
                    RoundedRectangle(cornerRadius: min(shape.size.width, shape.size.height) / 2)
                        .fill(Color.white)
                        .frame(width: shape.size.width, height: shape.size.height)
                        .shadow(color: Color(red: 0.75, green: 0.95, blue: 1.0).opacity(0.85), radius: 28)
                        .shadow(color: .white.opacity(0.95), radius: 10)
                        .shadow(color: .white.opacity(0.7), radius: 3)
                        .opacity(shape.opacity)
                }
            }
            .frame(width: bounds.width, height: bounds.height)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
    }

    /// Vertical collapse, then horizontal collapse, then fade.
    private func currentShape(elapsed: TimeInterval) -> (size: CGSize, opacity: Double) {
        if elapsed < phase1End {
            // Phase 1: full-width white slab collapses vertically to a thin
            // line, with a small horizontal shrink toward the middle so the
            // CRT "implodes" instead of guillotining.
            let t = elapsed / phase1End
            let h = bounds.height * CGFloat(1.0 - pow(t, 0.7))
            let w = bounds.width * CGFloat(1.0 - 0.08 * pow(t, 0.7))
            return (CGSize(width: w, height: max(2, h)), 1.0)
        } else if elapsed < phase2End {
            // Phase 2: thin line shrinks horizontally to a small dot.
            let t = (elapsed - phase1End) / (phase2End - phase1End)
            let w = bounds.width * CGFloat(1.0 - pow(t, 0.6))
            let dotW = max(4, w)
            return (CGSize(width: dotW, height: 3), 1.0)
        } else if elapsed < phase3End {
            // Phase 3: dot pulses briefly then fades.
            let t = (elapsed - phase2End) / (phase3End - phase2End)
            let pulse: CGFloat = 6 + 2 * CGFloat(sin(t * .pi * 4))
            let opacity = max(0.0, 1.0 - t * 1.2)
            return (CGSize(width: pulse, height: pulse), opacity)
        } else {
            return (CGSize(width: 0, height: 0), 0.0)
        }
    }
}
