import AppKit
import SwiftUI

/// In-app achievement banner shown when an easter egg is first discovered.
/// Top-center blue pill — deliberately distinct from the macOS notification
/// banner (which slides in from the top-right with glass material). The
/// system notification from `DiscoveryNotifier` still fires for
/// Notification Center history.
///
/// Rendered at `kCGPopUpMenuWindowLevel` (101) so it draws above the full-
/// screen egg panels (`kCGStatusWindowLevel` = 25).
@MainActor
enum AchievementBanner {
    private static var queue: [EasterEgg] = []
    private static var currentPanel: NSPanel?
    /// Panel is an oversized stage; the pill inside uses `.fixedSize()` so it
    /// hugs its content. Mouse events are ignored, so the invisible area
    /// doesn't block clicks.
    private static let panelSize = NSSize(width: 600, height: 80)
    private static let topMargin: CGFloat = 4
    private static let exitOffsetY: CGFloat = 24
    private static let holdDuration: TimeInterval = 3.5
    private static let exitDuration: TimeInterval = 0.18

    static func show(_ egg: EasterEgg) {
        queue.append(egg)
        if currentPanel == nil { showNext() }
    }

    private static func showNext() {
        guard !queue.isEmpty else { return }
        let egg = queue.removeFirst()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let visibleFrame = screen.visibleFrame
        let restingFrame = NSRect(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.maxY - panelSize.height - topMargin,
            width: panelSize.width,
            height: panelSize.height
        )
        // Exit-only motion: panel slides up + fades out after the hold.
        let exitFrame = restingFrame.offsetBy(dx: 0, dy: exitOffsetY)

        let panel = NSPanel(
            contentRect: restingFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // SwiftUI draws its own shadow under the capsule
        panel.alphaValue = 1.0  // no fade-in; the SwiftUI scale-pop is the entry
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        let host = NSHostingView(rootView: BannerView(egg: egg))
        host.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: NSRect(origin: .zero, size: panelSize))
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container
        panel.orderFrontRegardless()
        currentPanel = panel

        // Entry is SwiftUI-driven (scale spring in BannerView). Schedule the
        // fadeOutUp exit after the hold.
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) {
            MainActor.assumeIsolated {
                guard currentPanel === panel else { return }
                tween(panel: panel, from: restingFrame, to: exitFrame, startAlpha: 1, endAlpha: 0, duration: exitDuration) {
                    MainActor.assumeIsolated {
                        panel.orderOut(nil)
                        if currentPanel === panel { currentPanel = nil }
                        showNext()
                    }
                }
            }
        }
    }

    /// Non-blocking timer-driven frame + alpha tween with ease-out cubic.
    /// `setFrame(animate:)` blocks the main thread (freezing the very
    /// egg effect we're announcing) and `animator().setFrame` silently
    /// no-ops on borderless panels, so we drive the animation by hand.
    private static func tween(
        panel: NSPanel,
        from start: NSRect,
        to end: NSRect,
        startAlpha: CGFloat,
        endAlpha: CGFloat,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        panel.setFrameOrigin(NSPoint(x: start.minX, y: start.minY))
        panel.alphaValue = startAlpha
        let startTime = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { t in
            MainActor.assumeIsolated {
                let elapsed = Date().timeIntervalSince(startTime)
                let progress = min(1.0, elapsed / duration)
                let eased = 1 - pow(1 - progress, 3)
                let x = start.minX + (end.minX - start.minX) * eased
                let y = start.minY + (end.minY - start.minY) * eased
                panel.setFrameOrigin(NSPoint(x: x, y: y))
                panel.alphaValue = startAlpha + (endAlpha - startAlpha) * eased
                if progress >= 1.0 {
                    t.invalidate()
                    completion()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}

private struct BannerView: View {
    let egg: EasterEgg
    @State private var entered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(egg.emojiGlyph ?? "🎉")
                .font(.system(size: 20))
            Text("Easter egg discovered")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("·")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
            Text(egg.title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(nsColor: .systemBlue))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        )
        .fixedSize()  // pill width hugs content
        // Horizontal scale-pop: starts at ~14% width (≈ pill height → circle)
        // and snaps to 100% with a mild elastic overshoot (~peak 1.05).
        // y stays at 1.0 so text height doesn't squash. Anchor defaults to .center.
        .scaleEffect(x: entered ? 1.0 : 0.14, y: 1.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)  // center pill within the oversized panel stage
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                entered = true
            }
        }
    }
}
