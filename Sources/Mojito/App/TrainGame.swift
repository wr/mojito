import AppKit
import SwiftUI

/// Two fingers, one train. Goes from here... to here?
@MainActor
enum TrainGame {
    private static var activeWindow: NSWindow?

    static func start() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        activeWindow?.orderOut(nil)
        activeWindow = nil

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
                cancelToken?(); cancelToken = nil
                if activeWindow === panel { activeWindow = nil }
            }
        }

        let host = NSHostingView(rootView: TrainGameView(
            startDate: Date(),
            bounds: frame.size,
            onTap: dismiss
        ))
        host.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = host
        panel.orderFrontRegardless()
        activeWindow = panel

        cancelToken = EffectDismisser.register(dismiss)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            MainActor.assumeIsolated { dismiss() }
        }
    }
}

private struct TrainGameView: View {
    let startDate: Date
    let bounds: CGSize
    let onTap: () -> Void

    private let trainStartDelay: TimeInterval = 0.35
    private let trainRollDuration: TimeInterval = 1.6
    private let holdAtEnd: TimeInterval = 0.9

    private let fingerSize: CGFloat = 96
    private let trainSize: CGFloat = 80
    /// Horizontal margin from each screen edge to the finger center.
    private let edgeInset: CGFloat = 0.22

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let leftX = bounds.width * edgeInset
            let rightX = bounds.width * (1.0 - edgeInset)
            let baseY = bounds.height * 0.6
            // Train sits clear of the fingertips — at least half-finger +
            // half-train above the finger centers, plus padding.
            let trainY = baseY - (fingerSize + trainSize) / 2 - 12

            let trainX: CGFloat = {
                let t = (elapsed - trainStartDelay) / trainRollDuration
                let clamped = max(0.0, min(1.0, t))
                // Light ease-out so the train decelerates as it arrives.
                let eased = 1.0 - pow(1.0 - clamped, 2.0)
                return leftX + (rightX - leftX) * CGFloat(eased)
            }()

            ZStack {
                // Subtle dim so it reads as a moment, not an overlay bug.
                Color.black.opacity(0.18)

                Text("👆")
                    .font(.system(size: fingerSize))
                    .position(x: leftX, y: baseY)
                Text("👆")
                    .font(.system(size: fingerSize))
                    .position(x: rightX, y: baseY)

                Text("🚋")
                    .font(.system(size: trainSize))
                    .position(x: trainX, y: trainY)
            }
            .frame(width: bounds.width, height: bounds.height)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .opacity(opacity(elapsed: elapsed))
        }
    }

    private func opacity(elapsed: TimeInterval) -> Double {
        let total = trainStartDelay + trainRollDuration + holdAtEnd
        let fadeOut = 0.25
        if elapsed < fadeOut {
            return min(1.0, elapsed / fadeOut)
        }
        if elapsed > total {
            let t = (elapsed - total) / fadeOut
            return max(0.0, 1.0 - t)
        }
        return 1.0
    }
}
