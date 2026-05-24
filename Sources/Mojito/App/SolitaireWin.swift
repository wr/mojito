import AppKit
import SwiftUI

/// Classic Windows Solitaire victory cascade. Cards launch from the top-
/// right corner, fall under gravity, bounce off the bottom of the screen,
/// and leave colored trails behind them. 52 cards, ~8s total, click-through
/// overlay.
@MainActor
enum SolitaireWin {
    private static var activeWindow: NSWindow?

    static func start(duration: TimeInterval = 9.0) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        activeWindow?.orderOut(nil)
        activeWindow = nil

        // Build the deck — 52 cards launching from the top-right with
        // staggered launch times and slightly randomized initial velocities
        // so the cascade reads as a stream, not a single salvo.
        let suits: [CardSuit] = [.hearts, .diamonds, .clubs, .spades]
        let ranks: [String] = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
        var cards: [SolitaireCard] = []
        cards.reserveCapacity(52)
        var launchT: TimeInterval = 0
        for suit in suits {
            for rank in ranks {
                cards.append(SolitaireCard(
                    rank: rank,
                    suit: suit,
                    launchTime: launchT,
                    vx0: CGFloat.random(in: -380 ... -180),
                    vy0: CGFloat.random(in: -180 ... -40)
                ))
                launchT += 0.12
            }
        }

        let panel = ParticlePanel.makeFullScreen(frame: frame)
        let host = NSHostingView(rootView: SolitaireWinView(
            cards: cards,
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

private enum CardSuit: CaseIterable {
    case hearts, diamonds, clubs, spades
    var symbol: String {
        switch self {
        case .hearts:   return "♥"
        case .diamonds: return "♦"
        case .clubs:    return "♣"
        case .spades:   return "♠"
        }
    }
    var isRed: Bool { self == .hearts || self == .diamonds }
    /// Trail tint — picks one of the four classic Solitaire trail colors.
    var trailColor: Color {
        switch self {
        case .hearts:   return Color(red: 0.95, green: 0.20, blue: 0.30)
        case .diamonds: return Color(red: 0.95, green: 0.55, blue: 0.20)
        case .clubs:    return Color(red: 0.20, green: 0.55, blue: 0.95)
        case .spades:   return Color(red: 0.40, green: 0.85, blue: 0.40)
        }
    }
}

private struct SolitaireCard {
    let rank: String
    let suit: CardSuit
    let launchTime: TimeInterval
    let vx0: CGFloat
    let vy0: CGFloat
}

private struct SolitaireWinView: View {
    let cards: [SolitaireCard]
    let startDate: Date
    let bounds: CGSize
    let duration: TimeInterval

    private let cardWidth: CGFloat = 64
    private let cardHeight: CGFloat = 88
    private let gravity: CGFloat = 1100
    private let bounceDamping: CGFloat = 0.62

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            Canvas { ctx, _ in
                let endFade = elapsed > duration - 0.5
                    ? max(0.0, (duration - elapsed) / 0.5)
                    : 1.0

                // Origin point: just inside the top-right corner.
                let originX = bounds.width - cardWidth / 2 - 8
                let originY: CGFloat = 8 + cardHeight / 2

                for card in cards {
                    let t = elapsed - card.launchTime
                    guard t > 0 else { continue }

                    // Simulate ballistic + multiple floor bounces.
                    let (x, y, _) = positionWithBounces(
                        x0: originX,
                        y0: originY,
                        vx: card.vx0,
                        vy: card.vy0,
                        t: t,
                        floorY: bounds.height - cardHeight / 2,
                        gravity: gravity,
                        damping: bounceDamping
                    )

                    // Trail: stride backward in time, draw progressively
                    // smaller, more transparent dots along the path.
                    let trailSteps = 18
                    let trailStep: TimeInterval = 0.04
                    for i in 1...trailSteps {
                        let tt = t - Double(i) * trailStep
                        guard tt > 0 else { break }
                        let (tx, ty, _) = positionWithBounces(
                            x0: originX,
                            y0: originY,
                            vx: card.vx0,
                            vy: card.vy0,
                            t: tt,
                            floorY: bounds.height - cardHeight / 2,
                            gravity: gravity,
                            damping: bounceDamping
                        )
                        guard tx > -cardWidth, tx < bounds.width + cardWidth,
                              ty > -cardHeight, ty < bounds.height + cardHeight else { continue }
                        let fraction = Double(i) / Double(trailSteps)
                        let alpha = (1.0 - fraction) * 0.4 * Double(endFade)
                        let radius = CGFloat(8 * (1.0 - fraction))
                        var c = ctx
                        c.opacity = alpha
                        let rect = CGRect(x: tx - radius, y: ty - radius,
                                          width: radius * 2, height: radius * 2)
                        c.fill(Path(ellipseIn: rect), with: .color(card.suit.trailColor))
                    }

                    // Skip drawing the card itself once it's off to the left.
                    guard x > -cardWidth, y < bounds.height + cardHeight else { continue }

                    drawCard(ctx: ctx, card: card, x: x, y: y, opacity: Double(endFade))
                }
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .ignoresSafeArea()
    }

    /// Closed-form integrator with discrete bounce events. We track when
    /// the card's parabolic arc next intersects the floor; if that happens
    /// before `t`, we "consume" that bounce (advance start time + flip vy
    /// with damping) and continue. Doing this in a loop avoids per-frame
    /// state — every card's position is a pure function of `t`.
    private func positionWithBounces(
        x0: CGFloat, y0: CGFloat,
        vx: CGFloat, vy: CGFloat,
        t: TimeInterval,
        floorY: CGFloat,
        gravity: CGFloat,
        damping: CGFloat
    ) -> (CGFloat, CGFloat, CGFloat) {
        var px = x0
        var py = y0
        let vxCur = vx
        var vyCur = vy
        var tRemaining = CGFloat(t)
        // Hard cap on iterations — energy decays geometrically; in
        // practice we settle in <8 bounces. Cap prevents runaway loops
        // if vy is pathological.
        for _ in 0..<20 {
            // Time-to-floor for the current segment, solving:
            //   py + vy * t + 0.5 * g * t^2 = floorY
            let a = 0.5 * gravity
            let b = vyCur
            let c = py - floorY
            let disc = b * b - 4 * a * c
            let tFloor: CGFloat
            if disc >= 0 {
                let sq = sqrt(disc)
                let r1 = (-b + sq) / (2 * a)
                let r2 = (-b - sq) / (2 * a)
                // Want the smallest *positive* root.
                let candidates = [r1, r2].filter { $0 > 1e-4 }
                tFloor = candidates.min() ?? .infinity
            } else {
                tFloor = .infinity
            }

            if tFloor >= tRemaining {
                // No bounce within remaining time — integrate to end.
                px += vxCur * tRemaining
                py += vyCur * tRemaining + 0.5 * gravity * tRemaining * tRemaining
                // Approximate angular position from vx.
                return (px, py, vxCur * 0.02)
            }
            // Advance to the floor contact, then bounce.
            px += vxCur * tFloor
            py = floorY
            vyCur = -(vyCur + gravity * tFloor) * damping
            tRemaining -= tFloor
            // If the bounce is microscopic, give up to avoid burning iterations.
            if abs(vyCur) < 30 {
                px += vxCur * tRemaining
                return (px, py, vxCur * 0.02)
            }
        }
        return (px, py, 0)
    }

    private func drawCard(ctx: GraphicsContext, card: SolitaireCard, x: CGFloat, y: CGFloat, opacity: Double) {
        let rect = CGRect(x: x - cardWidth / 2, y: y - cardHeight / 2,
                          width: cardWidth, height: cardHeight)
        var c = ctx
        c.opacity = opacity
        // White face with thin gray border.
        c.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(.white))
        c.stroke(Path(roundedRect: rect, cornerRadius: 6),
                 with: .color(Color.black.opacity(0.35)), lineWidth: 1)

        let textColor: Color = card.suit.isRed
            ? Color(red: 0.85, green: 0.05, blue: 0.05)
            : .black

        // Rank top-left.
        let rank = Text(card.rank)
            .font(.system(size: 16, weight: .bold, design: .serif))
            .foregroundColor(textColor)
        c.draw(c.resolve(rank), at: CGPoint(x: rect.minX + 9, y: rect.minY + 12), anchor: .center)

        // Suit symbol below rank.
        let suitSmall = Text(card.suit.symbol)
            .font(.system(size: 14))
            .foregroundColor(textColor)
        c.draw(c.resolve(suitSmall), at: CGPoint(x: rect.minX + 9, y: rect.minY + 28), anchor: .center)

        // Big center suit.
        let suitBig = Text(card.suit.symbol)
            .font(.system(size: 32))
            .foregroundColor(textColor)
        c.draw(c.resolve(suitBig), at: CGPoint(x: rect.midX, y: rect.midY + 4), anchor: .center)
    }
}
