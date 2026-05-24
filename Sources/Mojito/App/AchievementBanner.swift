import AppKit
import SwiftUI

/// In-app achievement banner shown when an easter egg is first discovered.
/// Visually mirrors a macOS notification banner: ~22pt squircle corners,
/// `.hudWindow` glass, slides in from the right edge of the main screen.
/// Sits just below the menu bar, in the same screen position macOS uses
/// for notifications — so the OS chip can layer above it without overlap
/// if it fires too.
///
/// Rendered at `kCGPopUpMenuWindowLevel` (101) so it draws above the full-
/// screen egg panels (`kCGStatusWindowLevel` = 25). The system notification
/// from `DiscoveryNotifier` still fires for Notification Center history.
@MainActor
enum AchievementBanner {
    private static var queue: [EasterEgg] = []
    private static var currentPanel: NSPanel?
    private static let bannerSize = NSSize(width: 320, height: 64)
    private static let margin: CGFloat = 12
    private static let cornerRadius: CGFloat = 18
    private static let holdDuration: TimeInterval = 3.5

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
            x: visibleFrame.maxX - bannerSize.width - margin,
            y: visibleFrame.maxY - bannerSize.height - margin,
            width: bannerSize.width,
            height: bannerSize.height
        )
        // Off-screen to the right of the main screen edge — matches the
        // direction macOS notifications slide in from on Sonoma+.
        let offscreenFrame = restingFrame.offsetBy(dx: bannerSize.width + margin + 40, dy: 0)

        let panel = NSPanel(
            contentRect: offscreenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.alphaValue = 0.8
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        // AppKit glass background. SwiftUI's `.regularMaterial` inside a
        // borderless transparent NSPanel renders empty on macOS 14+;
        // NSVisualEffectView as the actual contentView is reliable. Same
        // pattern as DialupSound. `.popover` is a lighter, more subtle
        // glass than `.hudWindow`.
        let glass = NSVisualEffectView()
        glass.material = .sidebar
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = cornerRadius
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.translatesAutoresizingMaskIntoConstraints = false

        let host = NSHostingView(rootView: BannerView(
            egg: egg,
            discoveredCount: EasterEggTracker.discoveredCount,
            totalCount: EasterEggTracker.totalCount
        ))
        host.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            host.topAnchor.constraint(equalTo: glass.topAnchor),
            host.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        panel.contentView = glass
        panel.orderFrontRegardless()
        currentPanel = panel

        // Slide in. We can't use `panel.setFrame(animate:)` — it blocks
        // the main thread for the animation duration, which freezes the
        // very easter-egg effect we're announcing. `animator().setFrame`
        // silently no-ops on borderless panels. So we drive the slide
        // ourselves with a non-blocking Timer; cheap (60 Hz × 0.35 s ≈
        // 21 setFrameOrigin calls).
        slide(panel: panel, from: offscreenFrame, to: restingFrame) {
            DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) {
                MainActor.assumeIsolated {
                    guard currentPanel === panel else { return }
                    slide(panel: panel, from: restingFrame, to: offscreenFrame) {
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

    private static let slideDuration: TimeInterval = 0.35

    /// Non-blocking timer-driven setFrameOrigin animation with ease-out.
    private static func slide(
        panel: NSPanel,
        from start: NSRect,
        to end: NSRect,
        completion: @escaping () -> Void
    ) {
        let startTime = Date()
        let dur = slideDuration
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { t in
            MainActor.assumeIsolated {
                let elapsed = Date().timeIntervalSince(startTime)
                let progress = min(1.0, elapsed / dur)
                // Ease-out cubic: snappy entry, soft settle.
                let eased = 1 - pow(1 - progress, 3)
                let x = start.minX + (end.minX - start.minX) * eased
                let y = start.minY + (end.minY - start.minY) * eased
                panel.setFrameOrigin(NSPoint(x: x, y: y))
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
    let discoveredCount: Int
    let totalCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(egg.emojiGlyph ?? "🎉")
                .font(.system(size: 26))
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("Easter egg discovered")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(egg.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
