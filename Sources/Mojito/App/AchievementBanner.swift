import AppKit
import SwiftUI

@MainActor
final class BannerController: ObservableObject {
    @Published var visible: Bool = false
}

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
    private static let holdDuration: TimeInterval = 3.5
    private static let exitDuration: TimeInterval = 0.3

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

        let panel = NSPanel(
            contentRect: restingFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // SwiftUI draws its own shadow under the capsule
        panel.alphaValue = 1.0
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        let controller = BannerController()
        let host = NSHostingView(rootView: BannerView(egg: egg, controller: controller))
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

        // Entry + exit are both SwiftUI-driven scale springs in BannerView.
        // After the hold, flip `visible` to false to play the shrink-down,
        // then order the panel out once the spring has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) {
            MainActor.assumeIsolated {
                guard currentPanel === panel else { return }
                withAnimation(.easeIn(duration: 0.22)) {
                    controller.visible = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + exitDuration) {
                    MainActor.assumeIsolated {
                        panel.orderOut(nil)
                        if currentPanel === panel { currentPanel = nil }
                        showNext()
                    }
                }
            }
        }
    }
}

private struct BannerView: View {
    let egg: EasterEgg
    @ObservedObject var controller: BannerController

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
        // Bouncy scale-pop in/out from center. Both axes scale together so
        // the pill grows from a tiny dot into its resting size with an
        // elastic overshoot, and shrinks back to a dot on dismiss.
        .scaleEffect(controller.visible ? 1.0 : 0.0, anchor: .center)
        .opacity(controller.visible ? 1.0 : 0.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)  // center pill within the oversized panel stage
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) {
                controller.visible = true
            }
        }
    }
}
