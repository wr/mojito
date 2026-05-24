import AppKit
import AVFoundation
import SwiftUI

/// Swan Station countdown clock, split-flap style.
///
/// Each cell is a `FlipCard` with two flaps and two static back halves:
///   - back-top    = NEXT (revealed when top flap clears)
///   - back-bottom = CURRENT (covered until bottom flap lands)
///   - top flap    = CURRENT, hinged at bottom, falls 0° → -90° (phase 1)
///   - bottom flap = NEXT,   hinged at top,    rises +90° → 0° (phase 2)
/// Each flap carries its own (digit, theme) pair so color changes animate
/// in lockstep with the digit.
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

        // ~13s total: countdown + glyph cascade + wrap + hold.
        DispatchQueue.main.asyncAfter(deadline: .now() + 13.0) {
            MainActor.assumeIsolated { dismiss() }
        }
    }
}

// MARK: - SwiftUI shell

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
    /// Swan-Station-ish without using the canonical glyphs.
    private static let glyphs: [String] = ["𓂀", "𓃭", "𓆣", "𓊝", "𓆗", "𓋹"]

    /// Layout: [H_hundreds][H_tens][H_ones] [M_tens][M_ones]. Final = "108:00".
    @State private var cells: [String] = ["0", "0", "0", "0", "3"]
    @State private var phase: Phase = .countdown
    @State private var tickTimer: Timer?
    @State private var glyphTimers: [Timer?] = Array(repeating: nil, count: 5)
    /// Starts at 3 ("000:03"); wraps to 108 * 60 after the cascade.
    @State private var totalSeconds: Int = 3
    /// Cells owned by hieroglyphs — the tick skips these.
    @State private var capturedCells: Set<Int> = []
    /// Frozen-on-glyph cells. When all 5 are in here, the wrap fires.
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
                // Spacer so digits read as `HHH MM`, not crammed together.
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

    /// Minutes pair (3..4) inverts so it reads as a distinct module.
    /// Whole row goes red-on-black / black-on-red during the cascade.
    private func cellTheme(at index: Int) -> CellTheme {
        switch phase {
        case .hieroglyph:
            return index < 3 ? .redOnBlack : .blackOnRed
        default:
            return index < 3 ? .normal : .blackOnWhite
        }
    }

    private var colonColor: Color { .white }

    // MARK: Phase scheduling

    private let countdownTick: TimeInterval = 1.0
    private let resumeTick: TimeInterval = 1.0
    /// 200ms gives a satisfying glyph flicker.
    private let crazyFlipInterval: TimeInterval = 0.2
    private let crazyDuration: TimeInterval = 1.0
    private let stopStep: TimeInterval = 0.4

    private func runScript() {
        beginInitialCountdown()
    }

    private func beginInitialCountdown() {
        phase = .countdown
        capturedCells.removeAll()
        totalSeconds = 3
        refreshCells()
        startTicker(interval: countdownTick, onZero: { beginHieroglyphCascade() })
    }

    /// Resume from 108:00 until autoclose. If totalSeconds ever hits 0
    /// again, just loop back (won't in practice).
    private func resumeCountdownFrom108() {
        phase = .countdown
        capturedCells.removeAll()
        totalSeconds = 108 * 60
        refreshCells()
        startTicker(interval: resumeTick, onZero: nil)
    }

    /// `onZero` fires once when `totalSeconds` reaches 0; if nil, the
    /// counter wraps to 108:00 and keeps going.
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

    /// Format as `HHHMM` and write into each unowned cell.
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

    /// All 5 cells flip through random glyphs, then freeze one at a time
    /// in random order. When all 5 are frozen, the wrap chain fires.
    private func beginHieroglyphCascade() {
        phase = .hieroglyph
        stoppedCells.removeAll()
        capturedCells = Set(0..<5)
        let kickoffOffsets: [TimeInterval] = [0.00, 0.11, 0.04, 0.18, 0.07]
        for i in 0..<5 {
            scheduleCrazyFlip(for: i, after: kickoffOffsets[i])
        }
        let freezeOrder = (0..<5).shuffled()
        for (n, idx) in freezeOrder.enumerated() {
            let delay = crazyDuration + Double(n) * stopStep
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { freezeCell(idx) }
            }
        }
    }

    /// Rearms every `crazyFlipInterval` until the cell is frozen.
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

    /// Each slot snaps from its glyph to "0", then rolls 0 → 1 → … →
    /// target. Per-step dispatch so each mutation gets its own runloop
    /// tick — FlipCard's `.onChange(of: text)` fires a flip per step.
    private func beginWrap() {
        phase = .wrap
        let targets: [String] = ["1", "0", "8", "0", "0"]
        let stepDelay: TimeInterval = 0.15

        for slot in 0..<5 {
            let target = targets[slot]
            // Step 0 resets the glyph cell to "0"; then 1…target.
            var chain: [String] = ["0"]
            let endDigit = Int(target) ?? 0
            if endDigit != 0 {
                for d in 1...endDigit {
                    chain.append(String(d))
                }
            }

            // Stagger so columns cascade left-to-right.
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
        // monospacedDigit keeps columns aligned without SF Mono's slashed-zero.
        Text(":")
            .font(.system(size: 130, weight: .bold).monospacedDigit())
            .foregroundColor(color)
            .frame(width: 60, height: cellH)
    }
}

// MARK: - Flip card

/// Split-flap card. See `HatchClock`'s docstring for layer layout.
private struct FlipCard: View {
    let text: String
    let theme: CellTheme
    let cellW: CGFloat
    let cellH: CGFloat

    /// Settled state — back-bottom and resting top flap. Updated mid-flip
    /// once the top flap has cleared.
    @State private var currentDigit: String = " "
    @State private var currentTheme: CellTheme = .normal
    /// Upcoming state — back-top and bottom flap. Updated synchronously
    /// before each animation kicks off.
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
            // Back-top = NEXT (revealed once top flap clears).
            DigitHalf(
                digit: nextDigit,
                isTop: true,
                theme: nextTheme,
                cellW: cellW,
                cellH: cellH
            )
            .frame(width: cellW, height: cellH / 2, alignment: .top)
            .position(x: cellW / 2, y: cellH / 4)

            // Back-bottom = CURRENT (covered until bottom flap lands).
            DigitHalf(
                digit: currentDigit,
                isTop: false,
                theme: currentTheme,
                cellW: cellW,
                cellH: cellH
            )
            .frame(width: cellW, height: cellH / 2, alignment: .bottom)
            .position(x: cellW / 2, y: cellH * 3 / 4)

            // Top flap = CURRENT, hinged bottom, falls 0 → -90.
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

            // Bottom flap = NEXT, hinged top, rises +90 → 0.
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

            // Hinge hairline, crisps the seam.
            Rectangle()
                .fill(Color.black.opacity(0.7))
                .frame(width: cellW, height: 2)
                .position(x: cellW / 2, y: cellH / 2)

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
            // Theme can change without the digit (phase transitions).
            // Trigger a flip anyway so color transitions animate.
            if newTheme != currentTheme {
                triggerFlip(toDigit: text, toTheme: newTheme)
            }
        }
    }

    private func triggerFlip(toDigit newDigit: String, toTheme newTheme: CellTheme) {
        // Mid-flip: snap settled and continue. Can't perfectly queue without
        // visual hitches; this stays consistent.
        if isFlipping {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                currentDigit = nextDigit
                currentTheme = nextTheme
                topFlapAngle = 0
                bottomFlapAngle = 90
            }
        }
        if newDigit == currentDigit && newTheme == currentTheme {
            return
        }
        isFlipping = true
        HatchSounds.clack()

        // Stage `next` before animating so back-top and bottom flap
        // render the upcoming state. Top flap covers back-top; bottom
        // flap is rotated +90 (edge-on), so neither is visible yet.
        var t0 = Transaction(); t0.disablesAnimations = true
        withTransaction(t0) {
            nextDigit = newDigit
            nextTheme = newTheme
            topFlapAngle = 0
            bottomFlapAngle = 90
        }

        // Phase 1: top flap falls (showing OLD).
        withAnimation(.easeIn(duration: phase1)) {
            topFlapAngle = -90
        }

        // End of phase 1: commit `current` so back-bottom matches what
        // the bottom flap will land on, then raise the bottom flap.
        // Top flap snaps back to 0 — invisible because its content now
        // matches the back-top behind it.
        DispatchQueue.main.asyncAfter(deadline: .now() + phase1) {
            var t1 = Transaction(); t1.disablesAnimations = true
            withTransaction(t1) {
                currentDigit = newDigit
                currentTheme = newTheme
                topFlapAngle = 0
            }
            withAnimation(.easeOut(duration: phase2)) {
                bottomFlapAngle = 0
            }
        }

        // Reset bottom flap to +90 — invisible because back-bottom
        // already shows the same state.
        DispatchQueue.main.asyncAfter(deadline: .now() + phase1 + phase2) {
            var t2 = Transaction(); t2.disablesAnimations = true
            withTransaction(t2) {
                bottomFlapAngle = 90
            }
            isFlipping = false
        }
    }
}

/// One half of a digit. Trick: render the full-height glyph centered in a
/// full-cell frame, then clip to half — the visible part is the top or
/// bottom half of the glyph.
private struct DigitHalf: View {
    let digit: String
    let isTop: Bool
    let theme: CellTheme
    let cellW: CGFloat
    let cellH: CGFloat

    var body: some View {
        // Round only the outer two corners.
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: isTop ? 10 : 0,
            bottomLeadingRadius: isTop ? 0 : 10,
            bottomTrailingRadius: isTop ? 0 : 10,
            topTrailingRadius: isTop ? 10 : 0,
            style: .continuous
        )

        ZStack {
            shape.fill(theme.background)

            Text(digit)
                .font(.system(size: glyphFontSize(for: digit),
                              weight: glyphFontWeight(for: digit)).monospacedDigit())
                .foregroundColor(theme.foreground)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(width: cellW, height: cellH, alignment: .center)
                // Shift the full-height digit so the right half lands in
                // the half-frame: top half wants center at the bottom edge
                // (+cellH/4), bottom half wants center at the top (-cellH/4).
                .offset(y: isTop ? cellH / 4 : -cellH / 4)
        }
        .frame(width: cellW, height: cellH / 2)
        .clipShape(shape)
    }

    /// Hieroglyphs are denser and overflow at the digit size.
    private func glyphFontSize(for text: String) -> CGFloat {
        isHieroglyph(text) ? 100 : 150
    }

    private func glyphFontWeight(for text: String) -> Font.Weight {
        isHieroglyph(text) ? .heavy : .bold
    }

    private func isHieroglyph(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value >= 0x13000 && $0.value <= 0x1342F }
    }
}

/// Synthesized split-flap clack. Pool of 5 so near-simultaneous flips
/// don't cut each other off.
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

    /// ~10ms broadband click: differenced white noise (≈ brick-wall HP)
    /// + faint 4 kHz sine. Short + steep decay keeps it from reading as
    /// a pitched "thock".
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
            let raw = Double.random(in: -1...1)
            let hpNoise = raw - lastNoise
            lastNoise = raw
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
