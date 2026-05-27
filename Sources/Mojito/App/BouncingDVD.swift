import AppKit
import SwiftUI

/// Bouncing DVD logo. Triangle-wave reflection: per-axis distance drives
/// both position and wall-hit count from one number, so color cycles
/// can't drift away from actual collisions. Simultaneous both-axis
/// bounces inside `cornerTolerance` count as a corner hit.
@MainActor
enum BouncingDVD {
    private static var activeWindow: NSWindow?

    static func start() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        activeWindow?.orderOut(nil)
        activeWindow = nil

        // No auto-dismiss timer — runs until the user bails.
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Accept clicks so the SwiftUI tap handler fires.
        panel.ignoresMouseEvents = false
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        var cancelToken: (() -> Void)?
        let dismiss = {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                // Drop the tree so TimelineView stops firing — otherwise
                // physics runs invisibly and onCornerHit can re-fire.
                panel.contentView = nil
                cancelToken?(); cancelToken = nil
                if activeWindow === panel { activeWindow = nil }
            }
        }
        cancelToken = EffectDismisser.register(dismiss)

        let host = NSHostingView(rootView: BouncingDVDView(
            bounds: frame.size,
            startDate: Date(),
            onCornerHit: {
                MainActor.assumeIsolated {
                    // Corner hit = Perfect Bounce discovery (no shortcode).
                    let defaults = UserDefaults.standard
                    let next = (defaults.object(forKey: PrefsKey.perfectBounceCount) as? Int ?? 0) + 1
                    defaults.set(next, forKey: PrefsKey.perfectBounceCount)
                    EasterEggTracker.record(.k31)

                    ConfettiRain.start()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        MainActor.assumeIsolated { dismiss() }
                    }
                }
            },
            onTap: dismiss
        ))
        host.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = host
        panel.orderFrontRegardless()
        activeWindow = panel
    }
}

private struct BouncingDVDView: View {
    let bounds: CGSize
    let startDate: Date
    let onCornerHit: () -> Void
    let onTap: () -> Void

    private let logoSize = CGSize(width: 340, height: 180)
    /// Brisk enough that the DVD player feels like it's *trying*.
    private let velocity = CGVector(dx: 480, dy: 360)
    /// Tight so mid-flight pass-throughs don't count.
    private let cornerTolerance: CGFloat = 2

    /// Template so it can be tinted to the bounce color.
    private static let dvdImage: NSImage? = {
        let img = ImageBlob.load("v02")
        img?.isTemplate = true
        return img
    }()

    @State private var cornerHitFired = false
    /// Previous-frame bounce counts. Corner = both increment same frame.
    @State private var prevBouncesX = 0
    @State private var prevBouncesY = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let s = computeState(t: elapsed)
            let color = wallColor(for: s.bouncesX + s.bouncesY)

            // Within tolerance AND both axes bounced same frame — not
            // just "happens to be near a corner".
            let simultaneousBounce = s.bouncesX > prevBouncesX && s.bouncesY > prevBouncesY
            let realCornerHit = s.cornerProximity && simultaneousBounce && !cornerHitFired

            ZStack {
                Color.black.opacity(0.92).ignoresSafeArea()

                dvdLogo(color: realCornerHit ? .white : color)
                    .frame(width: logoSize.width, height: logoSize.height)
                    .position(x: s.position.x, y: s.position.y)
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .onChange(of: elapsed) { _, _ in
                if realCornerHit {
                    cornerHitFired = true
                    onCornerHit()
                }
                prevBouncesX = s.bouncesX
                prevBouncesY = s.bouncesY
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func dvdLogo(color: Color) -> some View {
        if let nsImage = Self.dvdImage {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(color)
        } else {
            Text(verbatim: "DVD")
                .font(.system(size: 96, weight: .black, design: .serif))
                .italic()
                .foregroundColor(color)
        }
    }

    /// Position + bounce counts + corner-proximity flag. The view body
    /// folds these into a real corner hit by also requiring both counters
    /// to increment in the same frame.
    private struct PhysicsState {
        let position: CGPoint
        let bouncesX: Int
        let bouncesY: Int
        let cornerProximity: Bool
    }

    /// Closed-form triangle-wave bouncing in an axis-aligned box.
    private func computeState(t: TimeInterval) -> PhysicsState {
        let halfW = logoSize.width / 2
        let halfH = logoSize.height / 2
        let innerW = bounds.width - logoSize.width
        let innerH = bounds.height - logoSize.height
        guard innerW > 0, innerH > 0 else {
            return PhysicsState(
                position: CGPoint(x: bounds.width / 2, y: bounds.height / 2),
                bouncesX: 0, bouncesY: 0, cornerProximity: false
            )
        }

        let distX = abs(velocity.dx) * CGFloat(t)
        let distY = abs(velocity.dy) * CGFloat(t)

        // Each cycle = innerW * 2 (across + back). Wall hits = floor.
        let bouncesX = Int(distX / innerW)
        let bouncesY = Int(distY / innerH)

        // Triangle wave: mod 2W, reflect past the midpoint.
        let modX = distX.truncatingRemainder(dividingBy: innerW * 2)
        let modY = distY.truncatingRemainder(dividingBy: innerH * 2)
        let xInRange = modX <= innerW ? modX : (innerW * 2 - modX)
        let yInRange = modY <= innerH ? modY : (innerH * 2 - modY)

        let posX = halfW + xInRange
        let posY = halfH + yInRange

        // Walls are at xInRange ≈ 0 or ≈ innerW.
        let distFromXWall = min(xInRange, innerW - xInRange)
        let distFromYWall = min(yInRange, innerH - yInRange)
        let cornerProximity = distFromXWall < cornerTolerance
            && distFromYWall < cornerTolerance
            && t > 0.5  // suppress the t=0 spawn corner

        return PhysicsState(
            position: CGPoint(x: posX, y: posY),
            bouncesX: bouncesX,
            bouncesY: bouncesY,
            cornerProximity: cornerProximity
        )
    }

    private let palette: [Color] = [
        Color(red: 1.0, green: 0.2, blue: 0.2),
        Color(red: 1.0, green: 0.55, blue: 0.1),
        Color(red: 1.0, green: 0.95, blue: 0.1),
        Color(red: 0.25, green: 0.95, blue: 0.35),
        Color(red: 0.0, green: 0.7, blue: 1.0),
        Color(red: 0.55, green: 0.3, blue: 0.95),
        Color(red: 1.0, green: 0.35, blue: 0.75),
    ]

    private func wallColor(for bounceCount: Int) -> Color {
        palette[((bounceCount % palette.count) + palette.count) % palette.count]
    }
}
