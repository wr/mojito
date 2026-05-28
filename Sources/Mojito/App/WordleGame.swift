import AppKit
import Observation
import SwiftUI

/// A five-letter guessing game in a regular game window. Key handling lives
/// on an NSWindow subclass — NSHostingView doesn't reliably put a child
/// responder in the chain, and NSEvent monitors are flaky for LSUIElement
/// apps. The secret word never changes.
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

        let size = NSSize(width: 400, height: 700)
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
        w.backgroundColor = .white
        // Light look sets it apart from the dark-themed games.
        w.appearance = NSAppearance(named: .aqua)
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
            if model.finished { model.reset() } else { model.submit() }
        case 49:            // Space restarts only once the round is over
            if model.finished { model.reset() }
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
}

@MainActor
@Observable
fileprivate final class WordleModel {
    static let answer = "emoji"
    static let maxGuesses = 6
    static let wordLength = 5

    private(set) var guesses: [String] = []
    private(set) var current: String = ""
    private(set) var won = false
    private(set) var lost = false
    private(set) var keyStates: [Character: LetterState] = [:]
    /// Bumped on an invalid (incomplete) submit so the view can shake.
    private(set) var shakeTick = 0

    var finished: Bool { won || lost }

    func reset() {
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
    }

    func backspace() {
        guard !finished, !current.isEmpty else { return }
        current.removeLast()
    }

    func submit() {
        guard !finished else { return }
        guard current.count == Self.wordLength else { shakeTick += 1; return }

        let guess = current
        let eval = evaluation(for: guess)
        for (i, c) in Array(guess).enumerated() { bump(c, to: eval[i]) }
        guesses.append(guess)
        current = ""

        if guess == Self.answer {
            won = true
        } else if guesses.count >= Self.maxGuesses {
            lost = true
        }
    }

    /// Two-pass scoring so duplicate letters in a guess don't all light up
    /// when the answer holds fewer copies.
    func evaluation(for guess: String) -> [LetterState] {
        let answer = Array(Self.answer)
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

    private let tileSize: CGFloat = 56
    private let tileGap: CGFloat = 6

    var body: some View {
        VStack(spacing: 14) {
            header
            grid
                .offset(x: shakeOffset)
            message
            Keyboard(model: model)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .onChange(of: model.shakeTick) { _, newValue in
            guard newValue > 0 else { return }
            shake()
        }
    }

    private var header: some View {
        Text(verbatim: "WORDLE")
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .tracking(6)
            .foregroundColor(WordlePalette.ink)
            .padding(.bottom, 2)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(WordlePalette.border)
                    .frame(height: 1)
                    .offset(y: 8)
            }
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
        let states: [LetterState]
        if row < model.guesses.count {
            let g = Array(model.guesses[row])
            letters = g
            states = model.evaluation(for: model.guesses[row])
        } else if row == model.guesses.count && !model.finished {
            let c = Array(model.current)
            letters = c
            states = c.map { _ in .filled }
        } else {
            letters = []
            states = []
        }

        return HStack(spacing: tileGap) {
            ForEach(0..<WordleModel.wordLength, id: \.self) { col in
                let letter = col < letters.count ? letters[col] : nil
                let state = col < states.count ? states[col] : LetterState.empty
                tile(letter: letter, state: state)
            }
        }
    }

    private func tile(letter: Character?, state: LetterState) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(WordlePalette.fill(state))
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(WordlePalette.tileBorder(state), lineWidth: 2)
            if let letter {
                Text(String(letter).uppercased())
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(WordlePalette.text(state))
            }
        }
        .frame(width: tileSize, height: tileSize)
    }

    @ViewBuilder
    private var message: some View {
        if model.won {
            VStack(spacing: 4) {
                Text(verbatim: winLabel)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(WordlePalette.correct)
                restartHint
            }
        } else if model.lost {
            VStack(spacing: 4) {
                Text(verbatim: WordleModel.answer.uppercased())
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundColor(WordlePalette.ink)
                restartHint
            }
        } else {
            Text(verbatim: "Guess the five-letter word")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(WordlePalette.subtle)
        }
    }

    private var restartHint: some View {
        Text(verbatim: "return to play again · esc to close")
            .font(.system(size: 11, weight: .regular, design: .rounded))
            .foregroundColor(WordlePalette.subtle)
    }

    private var winLabel: String {
        switch model.guesses.count {
        case 1:  return "Genius!"
        case 2:  return "Magnificent!"
        case 3:  return "Impressive!"
        case 4:  return "Splendid!"
        case 5:  return "Great!"
        default: return "Phew!"
        }
    }

    private func shake() {
        let step = 0.06
        let path: [CGFloat] = [-8, 8, -6, 6, 0]
        for (i, x) in path.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(i)) {
                withAnimation(.linear(duration: step)) { shakeOffset = x }
            }
        }
    }
}

private struct Keyboard: View {
    let model: WordleModel

    private let rows = ["qwertyuiop", "asdfghjkl"]

    var body: some View {
        VStack(spacing: 7) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(Array(row), id: \.self) { c in
                        letterKey(c)
                    }
                }
            }
            HStack(spacing: 5) {
                actionKey("ENTER", width: 52) {
                    if model.finished { model.reset() } else { model.submit() }
                }
                ForEach(Array("zxcvbnm"), id: \.self) { c in
                    letterKey(c)
                }
                actionKey("⌫", width: 52) { model.backspace() }
            }
        }
    }

    private func letterKey(_ c: Character) -> some View {
        let state = model.keyState(c)
        return Button {
            model.type(c)
        } label: {
            Text(String(c).uppercased())
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(WordlePalette.keyText(state))
                .frame(width: 31, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(WordlePalette.keyFill(state))
                )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private func actionKey(_ label: String, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(WordlePalette.keyText(.empty))
                .frame(width: width, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(WordlePalette.keyFill(.empty))
                )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}

/// Classic light-mode palette so the window reads as its own thing.
private enum WordlePalette {
    static let correct = Color(red: 0.42, green: 0.67, blue: 0.39)
    static let present = Color(red: 0.79, green: 0.71, blue: 0.35)
    static let absent  = Color(red: 0.47, green: 0.49, blue: 0.50)
    static let border  = Color(red: 0.83, green: 0.84, blue: 0.86)
    static let filledBorder = Color(red: 0.53, green: 0.54, blue: 0.55)
    static let ink     = Color(red: 0.10, green: 0.11, blue: 0.12)
    static let subtle  = Color(red: 0.47, green: 0.49, blue: 0.50)
    static let keyBase = Color(red: 0.83, green: 0.85, blue: 0.86)

    static func fill(_ s: LetterState) -> Color {
        switch s {
        case .correct: return correct
        case .present: return present
        case .absent:  return absent
        default:       return .white
        }
    }

    static func tileBorder(_ s: LetterState) -> Color {
        switch s {
        case .empty:  return border
        case .filled: return filledBorder
        default:      return .clear
        }
    }

    static func text(_ s: LetterState) -> Color {
        switch s {
        case .empty, .filled: return ink
        default:              return .white
        }
    }

    static func keyFill(_ s: LetterState) -> Color {
        switch s {
        case .correct: return correct
        case .present: return present
        case .absent:  return absent
        default:       return keyBase
        }
    }

    static func keyText(_ s: LetterState) -> Color {
        switch s {
        case .correct, .present, .absent: return .white
        default:                          return ink
        }
    }
}
