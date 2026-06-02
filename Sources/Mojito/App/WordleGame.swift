import AppKit
import Observation
import SwiftUI

/// A five-letter guessing game in a regular game window. Key handling lives
/// on an NSWindow subclass — NSHostingView doesn't reliably put a child
/// responder in the chain, and NSEvent monitors are flaky for LSUIElement
/// apps. Solving the first word unlocks a tougher bonus round.
@MainActor
enum WordleGame {
    fileprivate static var window: WordleWindow?
    private static var closeObserver: NSObjectProtocol?
    fileprivate static let model = WordleModel()

    static func start() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        model.reset()

        let size = NSSize(width: 380, height: 560)
        let w = WordleWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = ""
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = NSColor(WordlePalette.background)
        // Dark glass look, distinct from the original.
        w.appearance = NSAppearance(named: .darkAqua)
        w.isReleasedWhenClosed = false
        w.center()
        w.level = .floating

        let host = NSHostingView(rootView: WordleView(model: model))
        host.frame = CGRect(origin: .zero, size: size)
        w.contentView = host
        window = w
        DockIconManager.windowDidOpen()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: w,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if let obs = closeObserver {
                    NotificationCenter.default.removeObserver(obs)
                    closeObserver = nil
                }
                window = nil
                DockIconManager.windowDidClose()
            }
        }

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

fileprivate final class WordleWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        let model = WordleGame.model
        switch Int(event.keyCode) {
        case 53:            // Esc
            self.close()
        case 51:            // Delete
            model.backspace()
        case 36, 76:        // Return / keypad Enter
            if model.finished { model.advance() } else { model.submit() }
        case 49:            // Space advances once the round is over
            if model.finished { model.advance() }
        default:
            guard !event.modifierFlags.contains(.command),
                  let chars = event.charactersIgnoringModifiers,
                  chars.count == 1,
                  let c = chars.first, c.isLetter else { return }
            model.type(c)
        }
    }
}

fileprivate enum LetterState {
    case empty      // untouched
    case filled     // typed into the active row, not yet judged
    case correct    // right letter, right spot
    case present    // right letter, wrong spot
    case absent     // not in the word

    var revealTone: WordleSounds.RevealTone {
        switch self {
        case .correct: return .hit
        case .present: return .near
        default:       return .miss
        }
    }
}

fileprivate enum WordleStage { case main, bonus }

@MainActor
@Observable
fileprivate final class WordleModel {
    static let mainAnswer = "emoji"
    static let bonusAnswer = "fizzy"
    static let maxGuesses = 6
    static let wordLength = 5

    private(set) var stage: WordleStage = .main
    private(set) var guesses: [String] = []
    private(set) var current: String = ""
    private(set) var won = false
    private(set) var lost = false
    private(set) var keyStates: [Character: LetterState] = [:]
    /// Bumped on an invalid (incomplete) submit so the view can shake.
    private(set) var shakeTick = 0
    /// Bumped whenever the board is freshly cleared (reset or bonus advance)
    /// so the view can drop its per-tile animation state.
    private(set) var roundTick = 0

    var answer: String { stage == .main ? Self.mainAnswer : Self.bonusAnswer }
    var finished: Bool { won || lost }

    func reset() {
        stage = .main
        clearBoard()
        roundTick += 1
    }

    /// Return after a result: into the bonus round on a first-word win,
    /// otherwise back to a fresh main round.
    func advance() {
        if won && stage == .main {
            stage = .bonus
            clearBoard()
            roundTick += 1
        } else {
            reset()
        }
    }

    private func clearBoard() {
        guesses = []
        current = ""
        won = false
        lost = false
        keyStates = [:]
        shakeTick = 0
    }

    func type(_ c: Character) {
        guard !finished, current.count < Self.wordLength,
              let lower = c.lowercased().first, lower.isLetter else { return }
        current.append(lower)
        WordleSounds.tick()
    }

    func backspace() {
        guard !finished, !current.isEmpty else { return }
        current.removeLast()
    }

    func submit() {
        guard !finished else { return }
        guard current.count == Self.wordLength else {
            shakeTick += 1
            WordleSounds.invalid()
            return
        }

        let guess = current
        let eval = evaluation(for: guess)
        for (i, c) in Array(guess).enumerated() { bump(c, to: eval[i]) }
        guesses.append(guess)
        current = ""

        if guess == answer {
            won = true
        } else if guesses.count >= Self.maxGuesses {
            lost = true
        }
    }

    /// Called by the view once a row's flip-reveal animation has finished,
    /// so win/lose audio and the egg unlock land with the colors, not before.
    func onRevealComplete() {
        guard finished else { return }
        if won {
            if stage == .main {
                WordleSounds.win()
                scheduleBonusJump()
            } else {
                // The follow-up egg is the reward for beating the bonus round.
                EasterEggTracker.record(.k51)
                WordleSounds.bonusWin()
            }
        } else if lost {
            WordleSounds.lose()
        }
    }

    /// Auto-advance into the bonus round once the win celebration has played —
    /// a "press return" cue was too easy to miss. Pressing return still jumps
    /// early; the guard keeps that from double-advancing.
    private func scheduleBonusJump() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.won, self.stage == .main else { return }
            self.advance()
        }
    }

    /// Two-pass scoring so duplicate letters in a guess don't all light up
    /// when the answer holds fewer copies.
    func evaluation(for guess: String) -> [LetterState] {
        let answer = Array(self.answer)
        let g = Array(guess)
        var result = [LetterState](repeating: .absent, count: g.count)
        var counts: [Character: Int] = [:]
        for c in answer { counts[c, default: 0] += 1 }

        for i in g.indices where i < answer.count && g[i] == answer[i] {
            result[i] = .correct
            counts[g[i]]! -= 1
        }
        for i in g.indices where result[i] != .correct {
            if let n = counts[g[i]], n > 0 {
                result[i] = .present
                counts[g[i]]! -= 1
            }
        }
        return result
    }

    func keyState(_ c: Character) -> LetterState {
        keyStates[c] ?? .empty
    }

    /// Keyboard hints only ever escalate: absent → present → correct.
    private func bump(_ c: Character, to s: LetterState) {
        if rank(s) > rank(keyStates[c] ?? .empty) { keyStates[c] = s }
    }

    private func rank(_ s: LetterState) -> Int {
        switch s {
        case .correct: return 3
        case .present: return 2
        case .absent:  return 1
        default:       return 0
        }
    }
}

private struct WordleView: View {
    let model: WordleModel

    @State private var shakeOffset: CGFloat = 0
    @State private var flipY: [Int: CGFloat] = [:]
    @State private var revealedFront: Set<Int> = []
    @State private var popScale: [Int: CGFloat] = [:]
    @State private var winHop: [Int: CGFloat] = [:]
    @State private var lastGuessCount = 0

    private let tileSize: CGFloat = 58
    private let tileGap: CGFloat = 7
    private let colRevealStep = 0.22

    var body: some View {
        VStack(spacing: 16) {
            stageBadge
            grid
                .offset(x: shakeOffset)
            message
                .frame(height: 50)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WordlePalette.backgroundGradient)
        .onChange(of: model.shakeTick) { _, newValue in
            guard newValue > 0 else { return }
            shake()
        }
        .onChange(of: model.guesses.count) { _, newValue in
            if newValue > lastGuessCount { revealRow(newValue - 1) }
            lastGuessCount = newValue
        }
        .onChange(of: model.current.count) { old, newValue in
            if newValue > old { popActiveTile(col: newValue - 1) }
        }
        .onChange(of: model.roundTick) { _, _ in resetAnimationState() }
    }

    // Constant height in both stages so the grid never shifts when the
    // bonus badge appears.
    private var stageBadge: some View {
        ZStack {
            if model.stage == .bonus {
                Text(verbatim: "BONUS ROUND")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundColor(WordlePalette.correct)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(WordlePalette.correct.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(WordlePalette.correct.opacity(0.4), lineWidth: 1))
            }
        }
        .frame(height: 30)
    }

    private var grid: some View {
        VStack(spacing: tileGap) {
            ForEach(0..<WordleModel.maxGuesses, id: \.self) { row in
                rowView(row)
            }
        }
    }

    private func rowView(_ row: Int) -> some View {
        let letters: [Character]
        let judged: [LetterState]
        var isJudgedRow = false
        if row < model.guesses.count {
            letters = Array(model.guesses[row])
            judged = model.evaluation(for: model.guesses[row])
            isJudgedRow = true
        } else if row == model.guesses.count && !model.finished {
            letters = Array(model.current)
            judged = letters.map { _ in .filled }
        } else {
            letters = []
            judged = []
        }

        return HStack(spacing: tileGap) {
            ForEach(0..<WordleModel.wordLength, id: \.self) { col in
                let idx = row * WordleModel.wordLength + col
                let letter = col < letters.count ? letters[col] : nil
                let baseState = col < judged.count ? judged[col] : LetterState.empty
                // A judged tile reads as "filled" until its flip exposes color.
                let shown = (isJudgedRow && !revealedFront.contains(idx)) ? LetterState.filled : baseState
                tile(letter: letter, state: shown, idx: idx)
            }
        }
    }

    private func tile(letter: Character?, state: LetterState, idx: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(WordlePalette.fill(state))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(WordlePalette.tileBorder(state), lineWidth: 2)
            if let letter {
                Text(String(letter).uppercased())
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(WordlePalette.text(state))
            }
        }
        .frame(width: tileSize, height: tileSize)
        .scaleEffect(x: 1, y: flipY[idx] ?? 1, anchor: .center)
        .scaleEffect(popScale[idx] ?? 1)
        .offset(y: winHop[idx] ?? 0)
        .shadow(
            color: WordlePalette.glow(state),
            radius: WordlePalette.glowRadius(state)
        )
    }

    @ViewBuilder
    private var message: some View {
        if model.won {
            VStack(spacing: 5) {
                Text(verbatim: winLabel)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(WordlePalette.correct)
                Text(verbatim: model.stage == .main
                     ? "bonus round incoming…"
                     : "return to play again · esc to close")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(WordlePalette.subtle)
            }
        } else if model.lost {
            VStack(spacing: 5) {
                Text(verbatim: "Out of guesses")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(WordlePalette.ink)
                Text(verbatim: "return to play again · esc to close")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(WordlePalette.subtle)
            }
        } else {
            Text(verbatim: model.stage == .bonus
                 ? "One more word. Make it count."
                 : "Guess the five-letter word")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(WordlePalette.subtle)
        }
    }

    private var winLabel: String {
        if model.stage == .bonus { return "Bonus cleared! 🍹" }
        switch model.guesses.count {
        case 1:  return "Genius!"
        case 2:  return "Magnificent!"
        case 3:  return "Impressive!"
        case 4:  return "Splendid!"
        case 5:  return "Great!"
        default: return "Phew!"
        }
    }

    // MARK: animations

    private func shake() {
        let step = 0.06
        let path: [CGFloat] = [-9, 9, -7, 7, -4, 4, 0]
        for (i, x) in path.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(i)) {
                withAnimation(.linear(duration: step)) { shakeOffset = x }
            }
        }
    }

    private func popActiveTile(col: Int) {
        let idx = model.guesses.count * WordleModel.wordLength + col
        popScale[idx] = 1.22
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
            popScale[idx] = 1
        }
    }

    private func revealRow(_ row: Int) {
        // Pressing return during the reveal advances the round and clears
        // animation state; guard every deferred closure so stragglers from a
        // superseded round don't write into the fresh board.
        let round = model.roundTick
        let states = model.evaluation(for: model.guesses[row])
        // Per-column scale step for the reveal SFX: only greens climb, indexed
        // by how many greens precede them so scattered hits still ascend cleanly.
        var greenStep = [Int](repeating: 0, count: states.count)
        var greens = 0
        for c in 0..<states.count where states[c].revealTone == .hit {
            greenStep[c] = greens
            greens += 1
        }
        for col in 0..<WordleModel.wordLength {
            let idx = row * WordleModel.wordLength + col
            let delay = Double(col) * colRevealStep
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard model.roundTick == round else { return }
                // Center-anchored vertical scale, not a 3D rotation (which
                // juts in perspective).
                withAnimation(.easeIn(duration: 0.12)) { flipY[idx] = 0.04 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.12) {
                guard model.roundTick == round else { return }
                revealedFront.insert(idx)
                if col < states.count { WordleSounds.reveal(states[col].revealTone, step: greenStep[col]) }
                withAnimation(.easeOut(duration: 0.12)) { flipY[idx] = 1 }
            }
        }
        let endDelay = Double(WordleModel.wordLength - 1) * colRevealStep + 0.26
        DispatchQueue.main.asyncAfter(deadline: .now() + endDelay) {
            guard model.roundTick == round else { return }
            model.onRevealComplete()
            if model.won { winBounce(row: row, round: round) }
        }
    }

    private func winBounce(row: Int, round: Int) {
        for col in 0..<WordleModel.wordLength {
            let idx = row * WordleModel.wordLength + col
            let delay = Double(col) * 0.08
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard model.roundTick == round else { return }
                withAnimation(.spring(response: 0.26, dampingFraction: 0.42)) { winHop[idx] = -18 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
                    guard model.roundTick == round else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { winHop[idx] = 0 }
                }
            }
        }
    }

    private func resetAnimationState() {
        flipY = [:]
        revealedFront = []
        popScale = [:]
        winHop = [:]
        shakeOffset = 0
        lastGuessCount = 0
    }
}

/// Mint/lime on dark glass — its own identity, not the classic palette.
private enum WordlePalette {
    static let background = Color(red: 0.07, green: 0.08, blue: 0.09)
    static let backgroundGradient = LinearGradient(
        colors: [Color(red: 0.10, green: 0.12, blue: 0.13),
                 Color(red: 0.06, green: 0.07, blue: 0.08)],
        startPoint: .top, endPoint: .bottom
    )

    static let correct = Color(red: 0.56, green: 0.85, blue: 0.36)   // lime
    static let present = Color(red: 0.93, green: 0.71, blue: 0.29)   // amber
    static let absent  = Color(red: 0.24, green: 0.27, blue: 0.31)   // slate

    static let emptyFill = Color(red: 0.12, green: 0.14, blue: 0.16)
    static let emptyBorder = Color.white.opacity(0.12)
    static let filledBorder = Color.white.opacity(0.38)

    static let ink    = Color(red: 0.95, green: 0.96, blue: 0.94)    // cream
    static let subtle = Color.white.opacity(0.5)

    static func fill(_ s: LetterState) -> Color {
        switch s {
        case .correct: return correct
        case .present: return present
        case .absent:  return absent
        default:       return emptyFill
        }
    }

    static func tileBorder(_ s: LetterState) -> Color {
        switch s {
        case .empty:  return emptyBorder
        case .filled: return filledBorder
        default:      return .clear
        }
    }

    static func text(_ s: LetterState) -> Color {
        switch s {
        case .correct, .present: return Color(red: 0.08, green: 0.10, blue: 0.07) // dark on bright
        default:                 return ink
        }
    }

    /// A soft glow on the bright revealed states adds life against the dark.
    static func glow(_ s: LetterState) -> Color {
        switch s {
        case .correct: return correct.opacity(0.55)
        case .present: return present.opacity(0.45)
        default:       return .clear
        }
    }

    static func glowRadius(_ s: LetterState) -> CGFloat {
        switch s {
        case .correct, .present: return 9
        default:                 return 0
        }
    }
}
