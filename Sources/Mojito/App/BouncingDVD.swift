import AppKit
import SwiftUI

/// Bouncing DVD logo, the eternal screensaver.
///
/// Logo bounces against the four screen edges. Color cycles only at the
/// moment the logo touches a wall — never mid-flight, so the visual matches
/// the lore. If a collision happens to land within a small tolerance of a
/// corner (logo center within ~6 px of where both axes flip simultaneously),
/// it counts as a "corner hit" — the logo briefly flashes white, the screen
/// celebrates, and the effect dismisses.
///
/// Position uses a triangle wave for clean reflection at the edges. The
/// previous integer "bounceCount" approach drifted (because the modulo
/// math used `truncatingRemainder` which is biased) and made the logo fall
/// short of the screen edges. Here we compute distance traveled along each
/// axis, derive both the position and the wall-hit count from the same
/// number, and color-change only when that count increments.
@MainActor
enum BouncingDVD {
    private static var activeWindow: NSWindow?

    static func start() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        activeWindow?.orderOut(nil)
        activeWindow = nil

        // Build the panel up front, then create the dismiss closure that
        // both the view (click handler) and EffectDismisser (Esc handler)
        // can call. No auto-dismiss timer — DVD runs until the user bails.
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Accept clicks so the SwiftUI tap handler can dismiss; the screen-
        // saver vibe requires we feel like a full-screen capture.
        panel.ignoresMouseEvents = false
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        var cancelToken: (() -> Void)?
        let dismiss = {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                // Tear down the SwiftUI tree so the TimelineView stops
                // requesting frames. Without this the bouncing physics
                // keeps running invisibly and can keep firing onCornerHit
                // even after the panel is hidden.
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
                    // Bump the persistent counter and record discovery —
                    // hitting a corner is the secondary "Perfect Bounce"
                    // discovery trigger (no shortcode required).
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

    /// Logo dimensions (rendered size; the SVG is scaled to fit).
    private let logoSize = CGSize(width: 340, height: 180)
    /// Velocity per axis. Bumped up from a sleepy ~230/175 to something
    /// that feels like the DVD player is *trying* to corner-hit.
    private let velocity = CGVector(dx: 480, dy: 360)
    /// How close (in px) the logo must come to a corner AT THE MOMENT both
    /// axes simultaneously hit a wall to count as a "corner hit". Tight
    /// (was 8) — the previous looser threshold fired whenever the logo
    /// happened to pass through any corner region, including mid-flight.
    private let cornerTolerance: CGFloat = 2

    /// DVD logo loaded from the scrambled bundle. Drawn template-style so
    /// we can tint it with the active wall-bounce color.
    private static let dvdImage: NSImage? = {
        let img = ImageBlob.load("v02")
        img?.isTemplate = true
        return img
    }()

    @State private var cornerHitFired = false
    /// Per-axis bounce counts as of the last frame. Used to detect a true
    /// simultaneous double-bounce: a corner hit only counts when BOTH
    /// bouncesX AND bouncesY incremented since the previous frame.
    @State private var prevBouncesX = 0
    @State private var prevBouncesY = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let s = computeState(t: elapsed)
            let color = wallColor(for: s.bouncesX + s.bouncesY)

            // True corner hit: position is within tolerance of a corner
            // AND both axes' bounce counters incremented since the last
            // frame (i.e. both walls were hit in the same frame interval,
            // not just "logo happens to be near a corner").
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

    /// DVD logo content — bundled SVG tinted to `color`.
    @ViewBuilder
    private func dvdLogo(color: Color) -> some View {
        if let nsImage = Self.dvdImage {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(color)
        } else {
            // Fallback if the SVG didn't bundle: text "DVD".
            Text("DVD")
                .font(.system(size: 96, weight: .black, design: .serif))
                .italic()
                .foregroundColor(color)
        }
    }

    /// One-shot computation of position, per-axis wall-bounce counts, and
    /// corner-proximity flag at time `t`. The view body folds these into a
    /// real "corner hit" by also requiring both counters to increment in
    /// the same frame.
    private struct PhysicsState {
        let position: CGPoint
        let bouncesX: Int
        let bouncesY: Int
        let cornerProximity: Bool
    }

    /// Closed-form triangle-wave bouncing inside an axis-aligned box. Each
    /// axis tracks its own bounce count; the total is the sum.
    private func computeState(t: TimeInterval) -> PhysicsState {
        let halfW = logoSize.width / 2
        let halfH = logoSize.height / 2
        let innerW = bounds.width - logoSize.width    // travel range along x
        let innerH = bounds.height - logoSize.height
        guard innerW > 0, innerH > 0 else {
            return PhysicsState(
                position: CGPoint(x: bounds.width / 2, y: bounds.height / 2),
                bouncesX: 0, bouncesY: 0, cornerProximity: false
            )
        }

        // Distance traveled along each axis since start.
        let distX = abs(velocity.dx) * CGFloat(t)
        let distY = abs(velocity.dy) * CGFloat(t)

        // Each "cycle" along x covers `innerW * 2` (across and back).
        // Number of wall hits along x = floor(distX / innerW).
        let bouncesX = Int(distX / innerW)
        let bouncesY = Int(distY / innerH)

        // Triangle-wave position: take distance modulo 2*innerW, then
        // reflect if past the midpoint.
        let modX = distX.truncatingRemainder(dividingBy: innerW * 2)
        let modY = distY.truncatingRemainder(dividingBy: innerH * 2)
        let xInRange = modX <= innerW ? modX : (innerW * 2 - modX)
        let yInRange = modY <= innerH ? modY : (innerH * 2 - modY)

        let posX = halfW + xInRange
        let posY = halfH + yInRange

        // Corner-hit detection: are we within `cornerTolerance` of a wall on
        // BOTH axes at the same time? The position-along-axis hits a wall
        // when xInRange ≈ 0 or xInRange ≈ innerW.
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
