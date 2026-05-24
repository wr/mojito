import AppKit
import SwiftUI

/// In-app achievement banner shown when an easter egg is first discovered.
/// Rendered at `kCGPopUpMenuWindowLevel` (101) so it draws above the full-
/// screen egg panels (which sit at `kCGStatusWindowLevel` = 25). The system
/// notification from `DiscoveryNotifier` still fires alongside this banner
/// for Notification Center history — this is the primary, guaranteed signal.
@MainActor
enum AchievementBanner {
    private static var queue: [EasterEgg] = []
    private static var currentPanel: NSPanel?

    static func show(_ egg: EasterEgg) {
        queue.append(egg)
        if currentPanel == nil { showNext() }
    }

    private static func showNext() {
        guard !queue.isEmpty else { return }
        let egg = queue.removeFirst()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let bannerSize = NSSize(width: 360, height: 80)
        let margin: CGFloat = 16
        let visibleFrame = screen.visibleFrame
        let restingOrigin = NSPoint(
            x: visibleFrame.maxX - bannerSize.width - margin,
            y: visibleFrame.maxY - bannerSize.height - margin
        )
        // Off-screen above the resting position; we animate down into place.
        let offscreenOrigin = NSPoint(x: restingOrigin.x, y: restingOrigin.y + bannerSize.height + margin + 40)

        let panel = NSPanel(
            contentRect: NSRect(origin: offscreenOrigin, size: bannerSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        let total = EasterEggTracker.totalCount
        let discovered = EasterEggTracker.discoveredCount
        let host = NSHostingView(rootView: BannerView(
            egg: egg,
            discoveredCount: discovered,
            totalCount: total
        ))
        host.frame = NSRect(origin: .zero, size: bannerSize)
        panel.contentView = host
        panel.orderFrontRegardless()
        currentPanel = panel

        // Slide in.
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(restingOrigin)
        })

        // Hold ~3.5 s, slide out, then dequeue the next banner.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 + 3.5) {
            MainActor.assumeIsolated {
                guard currentPanel === panel else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.35
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    panel.animator().setFrameOrigin(offscreenOrigin)
                    panel.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated {
                        panel.orderOut(nil)
                        if currentPanel === panel { currentPanel = nil }
                        showNext()
                    }
                })
            }
        }
    }
}

private struct BannerView: View {
    let egg: EasterEgg
    let discoveredCount: Int
    let totalCount: Int

    // Sampled from the bundled app icons (also used by DialupView).
    private let mojitoOrange = Color(red: 0.95, green: 0.70, blue: 0.25)

    var body: some View {
        HStack(spacing: 14) {
            Text(egg.emojiGlyph ?? "🎉")
                .font(.system(size: 36))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Easter egg discovered")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(mojitoOrange)
                    .textCase(.uppercase)
                Text(egg.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(discoveredCount >= totalCount
                     ? "All \(totalCount) found"
                     : "\(discoveredCount) of \(totalCount)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.20), radius: 12, x: 0, y: 4)
        )
        .padding(2)
    }
}
