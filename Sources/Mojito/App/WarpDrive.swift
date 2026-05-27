import AppKit
import CoreGraphics

/// TNG-style jump to warp, in three phases over 10 seconds. The streaks
/// themselves are always white — color shows only as a 30px blurred halo
/// behind each streak during the acceleration phase.
///
///   0.0 – 2.0s  impulse        bright drifting dots, brightness varies
///                              per star — no halo
///   2.0 – 4.0s  acceleration   peak rate ~13×; ~720 stars total (extras
///                              biased toward the optical axis); 30px
///                              colored halo blooms in behind every streak
///   4.0 – 10s   cruise         medium-length white streaks, no halo; burst
///                              stars cycle off naturally to ~320
///   9.4 – 10s   exit           alpha fades to black
@MainActor
enum WarpDrive {
    private static var activeWindow: NSWindow?

    static func start(duration: TimeInterval = 10.0) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        activeWindow?.orderOut(nil)
        activeWindow = nil

        let panel = ParticlePanel.makeFullScreen(frame: frame)
        let view = WarpHostView(frame: NSRect(origin: .zero, size: frame.size), duration: duration)
        panel.contentView = view
        panel.orderFrontRegardless()
        activeWindow = panel

        WarpSound.play()

        var cancelToken: (() -> Void)?
        let dismiss = {
            MainActor.assumeIsolated {
                view.stop()
                WarpSound.stop()
                panel.orderOut(nil)
                cancelToken?(); cancelToken = nil
                if activeWindow === panel { activeWindow = nil }
            }
        }
        cancelToken = EffectDismisser.register(dismiss)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.4) {
            MainActor.assumeIsolated { dismiss() }
        }
    }
}

private struct WarpStar {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat
    var prevZ: CGFloat
    /// Halo tint — used only during acceleration. The streak itself is
    /// always white.
    var tintR: CGFloat
    var tintG: CGFloat
    var tintB: CGFloat
    /// Per-star brightness multiplier — drives alpha + line width so the
    /// impulse phase reads as a real starfield with bright + dim stars.
    var magnitude: CGFloat
}

@MainActor
private final class WarpHostView: NSView {
    private let duration: TimeInterval
    private var tickTimer: Timer?
    private var stars: [WarpStar] = []
    private let startDate = Date()
    private var lastFrameDate = Date()

    // Phase boundaries (seconds). No impulse drift; accel runs 0→3.0 then decel 3.0→3.5.
    private let impulseEnd: Double = 0.0
    private let accelPeak: Double  = 3.0
    private let accelEnd: Double   = 3.5
    /// Full-screen flash at the snap, landing just after peak velocity.
    private let flashStart: Double  = 3.15
    private let flashPeak: Double   = 3.2
    private let flashEnd: Double    = 3.7

    // Warp-rate set points (world-z per second).
    private let driftRate: CGFloat  = 0.04
    private let peakRate: CGFloat   = 22.0
    private let cruiseRate: CGFloat = 0.9

    // Single constant star count across all phases — splitting extras in
    // during accel made the new stars visibly "pop" at t=2s.
    private let starCount: Int = 400

    // Halo parameters — applied only during acceleration. CGContext shadow
    // blurs are GPU-bound but each one costs real time, so the draw loop
    // gates them on magnitude / nearness (see below) to skip the dim
    // background stars that contribute nothing visually anyway.
    private let haloBlur: CGFloat = 30
    private let haloOpacity: CGFloat = 0.35
    private let haloMagnitudeFloor: CGFloat = 0.85
    private let haloNearnessFloor: CGFloat = 0.15

    init(frame: NSRect, duration: TimeInterval) {
        self.duration = duration
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        buildStars()
        start()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func buildStars() {
        stars.reserveCapacity(starCount)
        for _ in 0..<starCount {
            stars.append(spawnStar(zRange: 0.15...1.5))
        }
    }

    private func spawnStar(zRange: ClosedRange<CGFloat>) -> WarpStar {
        let z = CGFloat.random(in: zRange)
        let x = CGFloat.random(in: -1.0...1.0)
        let y = CGFloat.random(in: -1.0...1.0)
        // Magnitude distribution — long tail of bright outliers, plenty of
        // dim background stars. Floor lifted vs the prior pass so even the
        // dimmest impulse stars register on a black backdrop.
        let mRoll = Int.random(in: 0..<100)
        let magnitude: CGFloat
        switch mRoll {
        case 0..<55:  magnitude = .random(in: 0.55...0.90)
        case 55..<85: magnitude = .random(in: 0.90...1.20)
        case 85..<97: magnitude = .random(in: 1.20...1.50)
        default:      magnitude = .random(in: 1.50...1.80)
        }
        let (r, g, b): (CGFloat, CGFloat, CGFloat)
        switch Int.random(in: 0..<100) {
        case 0..<40:  (r, g, b) = (0.85, 0.92, 1.00) // cool white-blue
        case 40..<62: (r, g, b) = (0.40, 0.70, 1.00) // saturated blue
        case 62..<78: (r, g, b) = (1.00, 0.50, 0.45) // saturated red-orange
        case 78..<90: (r, g, b) = (0.75, 0.50, 1.00) // violet
        default:      (r, g, b) = (1.00, 0.85, 0.35) // warm amber
        }
        return WarpStar(
            x: x, y: y, z: z, prevZ: z,
            tintR: r, tintG: g, tintB: b,
            magnitude: magnitude
        )
    }

    private func start() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.advance()
                }
            }
        }
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        stars.removeAll()
    }

    deinit {
        if let t = tickTimer { t.invalidate() }
    }

    private func warpRate(at t: Double) -> CGFloat {
        if t < impulseEnd { return driftRate }
        if t < accelPeak {
            let p = CGFloat((t - impulseEnd) / (accelPeak - impulseEnd))
            // Quintic ease-in: barely moves at first, hockey-sticks into the snap.
            let eased = pow(p, 5)
            return driftRate + (peakRate - driftRate) * eased
        }
        if t < accelEnd {
            let p = CGFloat((t - accelPeak) / (accelEnd - accelPeak))
            let eased = 1 - pow(1 - p, 3)
            return peakRate - (peakRate - cruiseRate) * eased
        }
        return cruiseRate
    }

    /// Brief white-out at the snap. Triangle envelope, 50ms in / 500ms out.
    private func flashAlpha(at t: Double) -> CGFloat {
        if t < flashStart || t > flashEnd { return 0 }
        if t < flashPeak {
            return CGFloat((t - flashStart) / (flashPeak - flashStart))
        }
        let p = CGFloat((t - flashPeak) / (flashEnd - flashPeak))
        // Quadratic ease-out for the fade so it doesn't linger.
        return 1.0 - p * p
    }

    /// Halo intensity. 0 during impulse and cruise; ramps in over the first
    /// 0.6s of acceleration, holds, then fades out over 0.4s into cruise.
    private func bloomStrength(at t: Double) -> CGFloat {
        if t < impulseEnd { return 0 }
        let rampEnd = impulseEnd + 0.6
        if t < rampEnd {
            let p = CGFloat((t - impulseEnd) / 0.6)
            return p * p * (3 - 2 * p)
        }
        if t < accelEnd { return 1.0 }
        let fadeEnd = accelEnd + 0.4
        if t < fadeEnd {
            let p = CGFloat((t - accelEnd) / 0.4)
            return 1.0 - p * p * (3 - 2 * p)
        }
        return 0
    }

    private func advance() {
        let now = Date()
        let dt = CGFloat(now.timeIntervalSince(lastFrameDate))
        lastFrameDate = now
        let elapsed = now.timeIntervalSince(startDate)
        let rate = warpRate(at: elapsed)

        for i in stars.indices {
            stars[i].prevZ = stars[i].z
            stars[i].z -= rate * dt
            if stars[i].z < 0.01 {
                stars[i] = spawnStar(zRange: 1.0...1.5)
            }
        }

        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let elapsed = Date().timeIntervalSince(startDate)
        let globalFade = elapsed > duration - 0.6
            ? max(0.0, (duration - elapsed) / 0.6)
            : 1.0
        let bloom = bloomStrength(at: elapsed)
        let useHalo = bloom > 0.05

        let w = bounds.width
        let h = bounds.height
        let cx = w / 2
        let cy = h / 2
        let projection = h * 1.1

        ctx.setLineCap(.round)

        for star in stars {
            let sx = star.x / star.z * projection + cx
            let sy = star.y / star.z * projection + cy
            let psx = star.x / star.prevZ * projection + cx
            let psy = star.y / star.prevZ * projection + cy

            if max(sx, psx) < -40 || min(sx, psx) > w + 40 ||
               max(sy, psy) < -40 || min(sy, psy) > h + 40 { continue }

            let nearness = max(0, min(1, 1.0 - star.z / 1.5))
            // Impulse-era brightness + thickness — magnitude scales both so
            // the field has visual depth, not a uniform pixel grid.
            let baseAlpha = (0.65 + 0.55 * nearness) * star.magnitude
            let alpha = min(1.0, baseAlpha) * globalFade
            let lineWidth = (1.2 + 2.5 * nearness) * star.magnitude

            // Halo: a 30px blurred shadow tinted with the star's color,
            // drawn beneath the white streak. Only applied to brighter /
            // closer stars — dim background stars contribute almost no
            // visible glow but each shadow stroke is expensive, so gating
            // here is what keeps the framerate up during peak acceleration.
            let drawHalo = useHalo
                && star.magnitude >= haloMagnitudeFloor
                && nearness >= haloNearnessFloor
            if drawHalo {
                ctx.saveGState()
                let haloAlpha = haloOpacity * bloom * globalFade
                let halo = NSColor(red: star.tintR, green: star.tintG, blue: star.tintB, alpha: haloAlpha)
                ctx.setShadow(offset: .zero, blur: haloBlur * bloom, color: halo.cgColor)
                ctx.setStrokeColor(NSColor(white: 1.0, alpha: alpha).cgColor)
                ctx.setLineWidth(lineWidth)
                ctx.move(to: CGPoint(x: psx, y: psy))
                ctx.addLine(to: CGPoint(x: sx, y: sy))
                ctx.strokePath()
                ctx.restoreGState()
            } else {
                ctx.setStrokeColor(NSColor(white: 1.0, alpha: alpha).cgColor)
                ctx.setLineWidth(lineWidth)
                ctx.move(to: CGPoint(x: psx, y: psy))
                ctx.addLine(to: CGPoint(x: sx, y: sy))
                ctx.strokePath()
            }
        }

        let flash = flashAlpha(at: elapsed) * globalFade
        if flash > 0.001 {
            // Cool-tinted wipe at sub-peak alpha — transitions without dazzling.
            let tinted = NSColor(red: 0.88, green: 0.94, blue: 1.0, alpha: flash * 0.85)
            ctx.setFillColor(tinted.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
    }
}
