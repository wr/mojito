import AppKit
import AVFoundation
import SwiftUI

/// The Swan Station countdown clock. Triggered by `:lost:`.
///
/// Architecture (rewritten — split-flap):
///   - Pure SwiftUI. Each digit cell is a `FlipCard` that owns its own
///     top-flap / bottom-flap angle state.
///   - Canonical split-flap / vestaboard animation: four layers per cell.
///       1. Static back top half  = NEXT (digit, theme)   — revealed when top flap finishes falling
///       2. Static back bottom half = CURRENT (digit, theme) — covered until bottom flap lands
///       3. Top flap (foreground) = CURRENT (digit, theme), hinged at BOTTOM, 0° → -90°
///       4. Bottom flap (foreground) = NEXT (digit, theme), hinged at TOP, +90° → 0°
///     Top flap falls first (phase 1), then bottom flap stands up (phase 2).
///   - Each FLAP carries its own (digit, theme) pair so that color changes
///     animate in lockstep with the digit change. During a flip:
///       - falling top flap + static bottom-back = OLD everything
///       - static top-back + rising bottom flap  = NEW everything
///   - The colon between hours and minutes is a plain static `Text(":")`,
///     NOT a flip card. It never animates and is given a fixed-width frame so
///     adjacent digit cards can't crowd it.
///   - Hieroglyph phase: 5 digit cells; first 3 (0,1,2) are red-on-black,
///     last 2 (3,4) are black-on-red. Each cell flips at a uniform 1.0s
///     cadence; per-cell start is offset by i * 0.1s so the row cascades
///     without per-flip jitter.
///   - End wrap (000:00 → 108:00): each cell first snaps to "0" (one flip
///     from whatever glyph it was showing), then rolls forward 0 → 1 → …
///     → target.
@MainActor
enum HatchClock {
    private static var activeWindow: NSWindow?

    static func start() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        activeWindow?.orderOut(nil)
        activeWindow = nil

        let panel = ParticlePanel.makeFullScreen(frame: frame)
        let host = NSHostingView(rootView: HatchView())
        host.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = host
        panel.orderFrontRegardless()
        activeWindow = panel

        var cancelToken: (() -> Void)?
        let dismiss = {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panel.contentView = nil
                cancelToken?(); cancelToken = nil
                if activeWindow === panel { activeWindow = nil }
            }
        }
        cancelToken = EffectDismisser.register(dismiss)

        // Total runtime budget:
        //   0.5s settle + 4s countdown (4 ticks @ 1s: 3→2→1→0) + 5s glyphs
        //   + 0.6s settle + 1.9s wrap chain + 2s hold = ~14s
        DispatchQueue.main.asyncAfter(deadline: .now() + 13.0) {
            MainActor.assumeIsolated { dismiss() }
        }
    }
}

// MARK: - SwiftUI shell

/// Color theme for a single cell.
private struct CellTheme: Equatable {
    let background: Color
    let foreground: Color

    static let normal = CellTheme(
        background: Color(white: 0.07),
        foreground: .white
    )
    static let redOnBlack = CellTheme(
        background: Color(white: 0.05),
        foreground: Color(red: 0.95, green: 0.18, blue: 0.08)
    )
    static let blackOnRed = CellTheme(
        background: Color(red: 0.85, green: 0.12, blue: 0.05),
        foreground: .black
    )
    static let blackOnWhite = CellTheme(
        background: .white,
        foreground: .black
    )
}

private enum Phase {
    case initialBlank
    case countdown
    case hieroglyph
    case wrap
    case hold
}

private struct HatchView: View {
    /// Hieroglyph pool. Reads as Swan-Station-ish without using the actual
    /// canonical glyphs.
    private static let glyphs: [String] = ["𓂀", "𓃭", "𓆣", "𓊝", "𓆗", "𓋹"]

    /// Final target = "108:00". Four digit cells: hundreds, tens, ones of
    /// hours; ones of minutes. (Tens of minutes shown via the 4th cell.)
    /// Layout: [H_hundreds][H_tens][H_ones] : [M_tens][M_ones]
    @State private var cells: [String] = ["0", "0", "0", "0", "3"]
    @State private var phase: Phase = .countdown
    @State private var tickTimer: Timer?
    @State private var glyphTimers: [Timer?] = Array(repeating: nil, count: 5)
    /// Total seconds remaining; refreshes the 5 visible cells each tick.
    /// Starts at 3 (display "000:03"). After the cycle wraps back to
    /// 108:00 it resumes from 108 * 60.
    @State private var totalSeconds: Int = 3
    /// Cells currently "owned" by hieroglyphs — the tick skips these so
    /// the captured glyphs persist while other cells continue ticking.
    @State private var capturedCells: Set<Int> = []
    /// Cells whose crazy-flip timer has been stopped — they're frozen
    /// on their last hieroglyph. When the set reaches 5, the wrap fires.
    @State private var stoppedCells: Set<Int> = []

    private let cellW: CGFloat = 140
    private let cellH: CGFloat = 200

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            HStack(spacing: 10) {
                FlipCard(text: cells[0], theme: cellTheme(at: 0), cellW: cellW, cellH: cellH)
                FlipCard(text: cells[1], theme: cellTheme(at: 1), cellW: cellW, cellH: cellH)
                FlipCard(text: cells[2], theme: cellTheme(at: 2), cellW: cellW, cellH: cellH)
                // Colon removed per user request — replaced with a fixed
                // transparent spacer so the digits stay visually grouped
                // as `HHH MM` rather than crammed together.
                Color.clear.frame(width: 30, height: cellH)
                FlipCard(text: cells[3], theme: cellTheme(at: 3), cellW: cellW, cellH: cellH)
                FlipCard(text: cells[4], theme: cellTheme(at: 4), cellW: cellW, cellH: cellH)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { runScript() }
        .onDisappear {
            tickTimer?.invalidate()
            tickTimer = nil
            for (i, t) in glyphTimers.enumerated() {
                t?.invalidate()
                glyphTimers[i] = nil
            }
        }
    }

    /// Per-cell theme.
    /// - Normal phases (countdown / wrap / hold): cells 0..2 are the
    ///   standard white-on-dark; cells 3..4 are black-on-white so the
    ///   minutes pair always reads as a distinct module.
    /// - Hieroglyph phase: cells 0..2 are red-on-black, cells 3..4 are
    ///   black-on-red. The whole row goes "crazy".
    private func cellTheme(at index: Int) -> CellTheme {
        switch phase {
        case .hieroglyph:
            return index < 3 ? .redOnBlack : .blackOnRed
        default:
            return index < 3 ? .normal : .blackOnWhite
        }
    }

    /// Colon stays plain white in every phase — turning it red during the
    /// hieroglyph cascade looked off against the alternating cell themes.
    private var colonColor: Color { .white }

    // MARK: Phase scheduling

    /// Initial countdown tick — 1s/tick so 000:03 → 000:00 takes 3s
    /// (each second visibly clicks down).
    private let countdownTick: TimeInterval = 1.0
    /// Post-wrap continued-tick interval — back to 1s/tick so the
    /// resumed countdown matches the initial countdown's cadence.
    private let resumeTick: TimeInterval = 1.0
    /// How fast each cell's crazy hieroglyph flip rearms during the
    /// frenetic phase. 200ms gives a satisfying flicker.
    private let crazyFlipInterval: TimeInterval = 0.2
    /// How long all 5 cells stay fully crazy before they start
    /// stopping one at a time.
    private let crazyDuration: TimeInterval = 1.0
    /// Gap between successive cell-stops during the freeze sequence.
    private let stopStep: TimeInterval = 0.4

    private func runScript() {
        // Start at 000:03 ticking down at 1s/tick. When the timer hits 0,
        // the cascade fires (cells captured one at a time, ticker stops).
        // After the cascade + wrap chain, we resume ticking from 108:00
        // at the faster `resumeTick` cadence until autoclose.
        beginInitialCountdown()
    }

    private func beginInitialCountdown() {
        phase = .countdown
        capturedCells.removeAll()
        totalSeconds = 3
        refreshCells()
        startTicker(interval: countdownTick, onZero: { beginHieroglyphCascade() })
    }

    /// Restart the ticker from 108:00 at the faster `resumeTick` rate.
    /// No transition on zero — if it ever reaches 0 it just loops back to
    /// 108:00 (it won't in practice; the window autocloses first).
    private func resumeCountdownFrom108() {
        phase = .countdown
        capturedCells.removeAll()
        totalSeconds = 108 * 60
        refreshCells()
        startTicker(interval: resumeTick, onZero: nil)
    }

    /// Single ticker driver. `onZero` is invoked exactly once when
    /// `totalSeconds` reaches 0; if nil, the counter wraps to 108:00 and
    /// keeps going.
    private func startTicker(interval: TimeInterval, onZero: (() -> Void)?) {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if totalSeconds <= 0 {
                        if let onZero = onZero {
                            tickTimer?.invalidate()
                            tickTimer = nil
                            onZero()
                        } else {
                            totalSeconds = 108 * 60
                            refreshCells()
                        }
                        return
                    }
                    totalSeconds -= 1
                    refreshCells()
                }
            }
        }
    }

    /// Format `totalSeconds` as `HHHMM` (3-digit minutes + 2-digit
    /// seconds) and write each character into its cell. Captured cells
    /// (owned by hieroglyphs) are skipped so they retain their glyph.
    private func refreshCells() {
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        let formatted = String(format: "%03d%02d", mins, secs)
        let chars = Array(formatted)
        for i in 0..<5 {
            if capturedCells.contains(i) { continue }
            assign(at: i, String(chars[i]))
        }
    }

    /// "Crazy hieroglyphs" cascade. All 5 cells immediately start
    /// flipping rapidly through random glyphs. After `crazyDuration`
    /// the cells begin to freeze one at a time in random order, each
    /// landing on whatever glyph happens to be showing when its timer
    /// is canceled. Once all 5 are frozen, the wrap chain fires.
    private func beginHieroglyphCascade() {
        phase = .hieroglyph
        stoppedCells.removeAll()
        // All 5 are owned by the hieroglyph layer — the ticker skips
        // them so the flickering glyphs aren't overwritten by digit
        // updates.
        capturedCells = Set(0..<5)
        let kickoffOffsets: [TimeInterval] = [0.00, 0.11, 0.04, 0.18, 0.07]
        for i in 0..<5 {
            scheduleCrazyFlip(for: i, after: kickoffOffsets[i])
        }
        // Freeze schedule: after `crazyDuration` of full chaos, start
        // stopping cells one at a time in random order.
        let freezeOrder = (0..<5).shuffled()
        for (n, idx) in freezeOrder.enumerated() {
            let delay = crazyDuration + Double(n) * stopStep
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { freezeCell(idx) }
            }
        }
    }

    /// One cell's crazy-flip loop. Picks a random glyph different from
    /// the current one and rearms itself every `crazyFlipInterval`
    /// until the cell is frozen (i.e. added to `stoppedCells`).
    private func scheduleCrazyFlip(for index: Int, after delay: TimeInterval) {
        let t = Timer.scheduledTimer(withTimeInterval: max(0.01, delay), repeats: false) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard phase == .hieroglyph,
                          !stoppedCells.contains(index) else { return }
                    let current = cells[index]
                    var pick = Self.glyphs.randomElement() ?? "𓂀"
                    var safety = 0
                    while pick == current && safety < 5 {
                        pick = Self.glyphs.randomElement() ?? "𓂀"
                        safety += 1
                    }
                    assign(at: index, pick)
                    scheduleCrazyFlip(for: index, after: crazyFlipInterval)
                }
            }
        }
        glyphTimers[index] = t
    }

    /// Stop one cell's crazy flip — it freezes on whatever glyph is
    /// currently showing. When all 5 are frozen, fire the wrap chain.
    private func freezeCell(_ index: Int) {
        stoppedCells.insert(index)
        glyphTimers[index]?.invalidate()
        glyphTimers[index] = nil
        if stoppedCells.count == 5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainActor.assumeIsolated { beginWrap() }
            }
        }
    }

    /// 0:00 → 108:00: each digit slot first snaps to "0" (one flip from
    /// whatever glyph it was showing), then rolls forward through
    /// intermediate digits to its target. We enqueue dispatches with a
    /// per-step delay; each mutation happens in its own runloop tick so
    /// SwiftUI sees the change and the FlipCard's `.onChange(of: text)`
    /// fires a flip per step.
    private func beginWrap() {
        phase = .wrap
        // Target = "108:00". Order: [0]="1", [1]="0", [2]="8", [3]="0", [4]="0".
        let targets: [String] = ["1", "0", "8", "0", "0"]
        let stepDelay: TimeInterval = 0.15

        for slot in 0..<5 {
            let target = targets[slot]
            // Build the per-slot flip chain.
            //   - Step 0: GLYPH → "0" (always — the cell was showing a
            //     hieroglyph, so first reset to a known numeric baseline).
            //   - Steps 1..N: 0 → 1 → 2 → … → target.
            //     If target == 0 the chain is just ["0"] (single flip).
            var chain: [String] = ["0"]
            let endDigit = Int(target) ?? 0
            if endDigit != 0 {
                for d in 1...endDigit {
                    chain.append(String(d))
                }
            }

            // Slight per-slot stagger so columns cascade left-to-right.
            let slotOffset = Double(slot) * 0.04
            for (step, value) in chain.enumerated() {
                let delay = slotOffset + Double(step) * stepDelay
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    MainActor.assumeIsolated {
                        assign(at: slot, value)
                    }
                }
            }
        }

        // After the wrap chain finishes, resume continuous ticking from
        // 108:00 at the faster `resumeTick` rate until the window
        // autocloses.
        let totalChain = 5 * 0.04 + 9 * stepDelay + 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + totalChain) {
            MainActor.assumeIsolated { resumeCountdownFrom108() }
        }
    }

    private func assign(at index: Int, _ value: String) {
        if cells[index] != value {
            cells[index] = value
        }
    }
}

// MARK: - Static colon

private struct Colon: View {
    let color: Color
    let cellH: CGFloat
    var body: some View {
        // Fixed width frame ensures the HStack reserves clear space for the
        // colon; adjacent digit cards can't crowd into it.
        Text(":")
            // SF Pro bold + `.monospacedDigit()` — keeps the digits
            // column-aligned without the slashed-zero of SF Mono.
            .font(.system(size: 130, weight: .bold).monospacedDigit())
            .foregroundColor(color)
            .frame(width: 60, height: cellH)
    }
}

// MARK: - Flip card

/// Canonical split-flap animation. Four layers, two flap angles.
///
/// Each FLAP carries its own (digit, theme) pair so theme changes animate
/// in sync with digit changes. The two "back" static halves and the two
/// foreground flap halves all sample from `current` or `next` independently:
///   - back-top      = NEXT  (revealed when top flap clears)
///   - back-bottom   = CURRENT (covered until bottom flap lands)
///   - top flap      = CURRENT (falls 0 → -90, hinged at bottom)
///   - bottom flap   = NEXT   (rises +90 → 0, hinged at top)
private struct FlipCard: View {
    let text: String
    let theme: CellTheme
    let cellW: CGFloat
    let cellH: CGFloat

    /// The "settled" (digit, theme) pair currently displayed by the
    /// static-back-bottom and the resting top flap. Updated mid-flip so the
    /// back's top (next) is revealed when the top flap clears.
    @State private var currentDigit: String = " "
    @State private var currentTheme: CellTheme = .normal
    /// The "next" (digit, theme) pair. Updated synchronously when `text`
    /// or `theme` changes, BEFORE the animation kicks off, so the back-top
    /// and bottom-flap render the upcoming state.
    @State private var nextDigit: String = " "
    @State private var nextTheme: CellTheme = .normal

    @State private var topFlapAngle: Double = 0      // 0 → -90 in phase 1
    @State private var bottomFlapAngle: Double = 90  // 90 → 0  in phase 2
    @State private var didInit: Bool = false
    @State private var isFlipping: Bool = false

    private let phase1: Double = 0.07
    private let phase2: Double = 0.07

    var body: some View {
        ZStack {
            // ----- Static back layers -----
            // Top half: shows the NEXT (digit, theme) — revealed when top flap falls.
            DigitHalf(
                digit: nextDigit,
                isTop: true,
                theme: nextTheme,
                cellW: cellW,
                cellH: cellH
            )
            .frame(width: cellW, height: cellH / 2, alignment: .top)
            .position(x: cellW / 2, y: cellH / 4)

            // Bottom half: shows the CURRENT (digit, theme) — covered until bottom flap lands.
            DigitHalf(
                digit: currentDigit,
                isTop: false,
                theme: currentTheme,
                cellW: cellW,
                cellH: cellH
            )
            .frame(width: cellW, height: cellH / 2, alignment: .bottom)
            .position(x: cellW / 2, y: cellH * 3 / 4)

            // ----- Foreground flaps -----
            // Top flap: CURRENT (digit, theme), hinged at bottom, falls 0 → -90.
            DigitHalf(
                digit: currentDigit,
                isTop: true,
                theme: currentTheme,
                cellW: cellW,
                cellH: cellH
            )
            .frame(width: cellW, height: cellH / 2, alignment: .top)
            .rotation3DEffect(
                .degrees(topFlapAngle),
                axis: (x: 1, y: 0, z: 0),
                anchor: .bottom,
                anchorZ: 0,
                perspective: 0.6
            )
            .position(x: cellW / 2, y: cellH / 4)

            // Bottom flap: NEXT (digit, theme), hinged at top, rises +90 → 0.
            DigitHalf(
                digit: nextDigit,
                isTop: false,
                theme: nextTheme,
                cellW: cellW,
                cellH: cellH
            )
            .frame(width: cellW, height: cellH / 2, alignment: .bottom)
            .rotation3DEffect(
                .degrees(bottomFlapAngle),
                axis: (x: 1, y: 0, z: 0),
                anchor: .top,
                anchorZ: 0,
                perspective: 0.6
            )
            .position(x: cellW / 2, y: cellH * 3 / 4)

            // Hairline at the hinge — sits on top of everything to crisp up
            // the seam between the two halves.
            Rectangle()
                .fill(Color.black.opacity(0.7))
                .frame(width: cellW, height: 2)
                .position(x: cellW / 2, y: cellH / 2)

            // Outer border, on top.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                .frame(width: cellW, height: cellH)
        }
        .frame(width: cellW, height: cellH)
        .onAppear {
            if !didInit {
                currentDigit = text
                currentTheme = theme
                nextDigit = text
                nextTheme = theme
                didInit = true
            }
        }
        .onChange(of: text) { _, newValue in
            triggerFlip(toDigit: newValue, toTheme: theme)
        }
        .onChange(of: theme) { _, newTheme in
            // Theme can change independently of digit (e.g. phase transition
            // back to .normal while the digit stays the same). Still trigger
            // a flip so the color transition animates rather than snapping.
            if newTheme != currentTheme {
                triggerFlip(toDigit: text, toTheme: newTheme)
            }
        }
    }

    private func triggerFlip(toDigit newDigit: String, toTheme newTheme: CellTheme) {
        // If already flipping, snap the in-flight animation to a settled
        // state for the new value (we can't perfectly queue without
        // visual hitches; this just keeps things consistent).
        if isFlipping {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                currentDigit = nextDigit
                currentTheme = nextTheme
                topFlapAngle = 0
                bottomFlapAngle = 90
            }
        }
        // If neither digit nor theme actually changed, nothing to do.
        if newDigit == currentDigit && newTheme == currentTheme {
            return
        }
        isFlipping = true
        HatchSounds.clack()

        // Set the "next" pair BEFORE animating so the back-top and the
        // bottom flap render the upcoming state immediately. The user can't
        // see them yet — the top flap covers the back-top, and the bottom
        // flap is rotated +90 (edge-on, invisible).
        var t0 = Transaction(); t0.disablesAnimations = true
        withTransaction(t0) {
            nextDigit = newDigit
            nextTheme = newTheme
            // Make sure the angles are at their phase-1 starting positions.
            topFlapAngle = 0
            bottomFlapAngle = 90
        }

        // Phase 1: top flap falls (showing OLD digit + OLD theme).
        withAnimation(.easeIn(duration: phase1)) {
            topFlapAngle = -90
        }

        // At end of phase 1, commit `current` to the new (digit, theme) so
        // the back-bottom now matches what the bottom flap will land on,
        // then animate the bottom flap up.
        DispatchQueue.main.asyncAfter(deadline: .now() + phase1) {
            var t1 = Transaction(); t1.disablesAnimations = true
            withTransaction(t1) {
                currentDigit = newDigit
                currentTheme = newTheme
                // Reset top flap instantly so the top half of the cell now
                // shows the (already-correct) back-top through it. Because
                // both current and next now equal the new state, the top
                // flap's content matches the back, so the instant angle
                // reset is invisible.
                topFlapAngle = 0
            }
            withAnimation(.easeOut(duration: phase2)) {
                bottomFlapAngle = 0
            }
        }

        // After phase 2, snap the bottom flap back to +90 (invisible) so
        // it's ready to rise for the next flip. Because the back-bottom
        // already shows the same state, the snap is invisible.
        DispatchQueue.main.asyncAfter(deadline: .now() + phase1 + phase2) {
            var t2 = Transaction(); t2.disablesAnimations = true
            withTransaction(t2) {
                bottomFlapAngle = 90
            }
            isFlipping = false
        }
    }
}

/// Renders one half (top or bottom) of a digit, clipped to a half-height
/// rounded-corner rectangle. The trick: draw the full-size digit centered
/// inside a frame that's the FULL cell height, then clip to the half. That
/// way the visible portion is exactly the top or bottom half of the glyph.
private struct DigitHalf: View {
    let digit: String
    let isTop: Bool
    let theme: CellTheme
    let cellW: CGFloat
    let cellH: CGFloat

    var body: some View {
        // The clipping shape: round only the outer two corners.
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: isTop ? 10 : 0,
            bottomLeadingRadius: isTop ? 0 : 10,
            bottomTrailingRadius: isTop ? 0 : 10,
            topTrailingRadius: isTop ? 10 : 0,
            style: .continuous
        )

        ZStack {
            // Background fill for this half.
            shape.fill(theme.background)

            // Full-size digit, centered. We pin it to a frame the height of
            // the WHOLE cell; the parent's half-height frame + .clipped()
            // crops it to just the relevant half. Hieroglyphs render ~20%
            // smaller than digits — they're visually denser glyphs and
            // would otherwise overflow the cell.
            Text(digit)
                .font(.system(size: glyphFontSize(for: digit),
                              weight: glyphFontWeight(for: digit)).monospacedDigit())
                .foregroundColor(theme.foreground)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(width: cellW, height: cellH, alignment: .center)
                // Offset shifts the FULL-size digit so the desired half
                // lands inside the half-height clipping window. The parent
                // frames this view at cellH/2; the digit's natural center
                // sits at cellH/2 from its top, so:
                //   - For top half: we want the digit's TOP half visible,
                //     i.e. the digit's vertical center at the BOTTOM edge of
                //     the half-frame → offset y = +cellH/4 (down).
                //   - For bottom half: we want the digit's BOTTOM half
                //     visible, i.e. center at the TOP edge of the half-frame
                //     → offset y = -cellH/4 (up).
                .offset(y: isTop ? cellH / 4 : -cellH / 4)
        }
        .frame(width: cellW, height: cellH / 2)
        .clipShape(shape)
    }

    /// 150pt for ASCII digits, 100pt for hieroglyphs. Hieroglyphs are
    /// visually denser glyphs and overflow the cell at the full digit
    /// size.
    private func glyphFontSize(for text: String) -> CGFloat {
        isHieroglyph(text) ? 100 : 150
    }

    /// Hieroglyphs get `.heavy` so the system font picks the thickest
    /// variant it has for the Egyptian Hieroglyphs block — usually a no-op
    /// (the block doesn't ship with weight variants in most fonts) but
    /// harmless if so.
    private func glyphFontWeight(for text: String) -> Font.Weight {
        isHieroglyph(text) ? .heavy : .bold
    }

    private func isHieroglyph(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value >= 0x13000 && $0.value <= 0x1342F }
    }
}

/// Code-synthesized split-flap "clack" — the mechanical click you hear
/// when a vestaboard / airport flip-clock flips. ~70 ms of a low-pitched
/// noise burst with a sharp exponential decay. A pool of 5 players lets
/// near-simultaneous cell flips overlap without cutting each other off.
@MainActor
enum HatchSounds {
    private static let poolSize = 5
    private static let pool: [AVAudioPlayer] = makePool()
    private static var nextIndex: Int = 0

    static func clack() {
        guard !pool.isEmpty else { return }
        let p = pool[nextIndex % pool.count]
        nextIndex &+= 1
        p.stop()
        p.currentTime = 0
        p.play()
    }

    private static func makePool() -> [AVAudioPlayer] {
        let data = makeClackWave()
        return (0..<poolSize).compactMap {
            _ in
            guard let p = try? AVAudioPlayer(data: data) else { return nil }
            p.volume = 0.30
            p.prepareToPlay()
            return p
        }
    }

    /// ~10 ms broadband click — mostly white noise high-passed by
    /// differencing consecutive samples, plus a faint high-sine kicker
    /// for a touch of pitched "snap". Very short duration + steep decay
    /// keeps it from reading as a pitched tone (which sounded "thocky"
    /// in the previous iteration).
    private static func makeClackWave() -> Data {
        let sampleRate: Double = 44100
        let duration: Double = 0.010
        let numSamples = Int(duration * sampleRate)
        let amplitude = Double(Int16.max) * 0.55

        var samples = [Int16]()
        samples.reserveCapacity(numSamples)
        var lastNoise: Double = 0
        var phase: Double = 0
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            // Differenced white noise = brick-wall high-pass; the result
            // has most of its energy at multi-kHz where "click" lives.
            let raw = Double.random(in: -1...1)
            let hpNoise = raw - lastNoise
            lastNoise = raw
            // Faint 4 kHz sine for a hint of pitched character.
            phase += 2 * .pi * 4000.0 / sampleRate
            let sine = sin(phase) * 0.25
            let mixed = hpNoise * 0.75 + sine
            let attack = min(1.0, t / 0.0002)
            let decay = exp(-t * 380)
            samples.append(Int16(amplitude * mixed * attack * decay))
        }

        let dataSize = samples.count * MemoryLayout<Int16>.size
        var data = Data()
        func writeUInt32LE(_ value: UInt32) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func writeUInt16LE(_ value: UInt16) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        writeUInt32LE(UInt32(36 + dataSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        writeUInt32LE(16)
        writeUInt16LE(1)
        writeUInt16LE(1)
        writeUInt32LE(UInt32(sampleRate))
        writeUInt32LE(UInt32(sampleRate) * 2)
        writeUInt16LE(2)
        writeUInt16LE(16)
        data.append(contentsOf: "data".utf8)
        writeUInt32LE(UInt32(dataSize))
        samples.withUnsafeBufferPointer { ptr in
            data.append(UnsafeBufferPointer(
                start: UnsafeRawPointer(ptr.baseAddress!).assumingMemoryBound(to: UInt8.self),
                count: dataSize
            ))
        }
        return data
    }
}
