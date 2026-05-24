import AppKit
import AVFoundation
import SwiftUI

/// "Shall we play a game?" — Tic-Tac-Toe in the WarGames style. Triggered by
/// `:globalthermonuclearwar:`.
///
/// 3×3 board, human plays X, computer plays O. The CPU runs full minimax —
/// optimal play means the best the user can do is a draw. (That's exactly
/// the punchline of the movie: the only winning move is not to play.)
///
/// Visual treatment matches the 1983 film's WOPR display: thick glowing
/// cyan X's and O's on a deep blue-black background, drawn with stroked
/// shapes (not text) so they look like vector CRT graphics rather than
/// terminal glyphs. After the stalemate the board clears and the famous
/// "A STRANGE GAME..." monologue types out one character at a time.
@MainActor
enum TicTacToeGame {
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    /// Closes the active game window if one is up. Called from the view
    /// once the monologue finishes typing and the hold elapses.
    static func dismiss() {
        window?.close()
    }

    static func start() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Width sized to fit the widest monologue line at 22pt monospace
        // + tracking 2 without forcing SwiftUI to wrap.
        let size = NSSize(width: 640, height: 640)
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = ""
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = NSColor(red: 0.01, green: 0.03, blue: 0.08, alpha: 1)
        w.appearance = NSAppearance(named: .darkAqua)
        w.isReleasedWhenClosed = false
        w.center()
        w.level = .floating

        let host = NSHostingView(rootView: TicTacToeView())
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

private enum Mark: String {
    case empty = " "
    case x = "X"
    case o = "O"
}

private struct TicTacToeView: View {
    @State private var board: [Mark] = Array(repeating: .empty, count: 9)
    @State private var humanTurn = true
    @State private var status: String = "SHALL WE PLAY A GAME?"
    @State private var done = false
    /// When non-nil the board hides and we display the typewriter monologue
    /// instead. `typedCount` is how many characters of the full string have
    /// been rendered so far.
    @State private var showMonologue = false
    @State private var typedCount: Int = 0
    @State private var typeTimer: Timer?
    @State private var speechSynth: NSSpeechSynthesizer?
    @State private var speechDelegate: SpeechDelegate?
    /// Wall-clock time the typewriter is allowed to resume. Set whenever
    /// we hit a paragraph break (`\n\n`) so the on-screen pause roughly
    /// matches the narration's `[[slnc …]]` beat.
    @State private var typeResumeAt: Date?

    /// CRT cyan — the glowing WOPR screen color from the film.
    private let crtCyan = Color(red: 0.55, green: 0.92, blue: 1.0)
    private let crtCyanDim = Color(red: 0.35, green: 0.62, blue: 0.78)
    /// Deep blue-black background — slightly bluer than pure black.
    private let crtBg = Color(red: 0.01, green: 0.03, blue: 0.08)

    private let monologue = "A STRANGE GAME.\nTHE ONLY WINNING MOVE IS\nNOT TO PLAY.\n\nHOW ABOUT A NICE GAME OF CHESS?"

    var body: some View {
        ZStack {
            crtBg.ignoresSafeArea()

            if showMonologue {
                monologueView
            } else {
                gameView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gameView: some View {
        VStack(spacing: 22) {
            Spacer().frame(height: 12)

            Text("MJTO — STRATEGIC COMMAND")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(crtCyanDim)
                .tracking(4)

            Text(status)
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundColor(crtCyan)
                .tracking(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .frame(minHeight: 52)
                .shadow(color: crtCyan.opacity(0.7), radius: 6)

            grid

            Spacer().frame(height: 18)
        }
    }

    /// 3x3 WarGames grid. Like the film, the grid is drawn as four
    /// freestanding lines (a `#` shape) — no cell borders, no outer frame.
    /// Marks are stroked shapes (not text) for the chunky vector-CRT look.
    private var grid: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { col in
                            let idx = row * 3 + col
                            Button(action: { play(idx) }) {
                                ZStack {
                                    switch board[idx] {
                                    case .x:
                                        WOPRMarkX()
                                            .stroke(crtCyan, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                            .padding(18)
                                            .shadow(color: crtCyan.opacity(0.85), radius: 8)
                                    case .o:
                                        Circle()
                                            .stroke(crtCyan, lineWidth: 8)
                                            .padding(18)
                                            .shadow(color: crtCyan.opacity(0.85), radius: 8)
                                    case .empty:
                                        EmptyView()
                                    }
                                }
                                .frame(width: 110, height: 110)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                            // No `.disabled` — it dims the placed mark via
                            // SwiftUI's standard disabled-control treatment,
                            // making X/O look paler than the grid lines.
                            // `play(_:)` already no-ops if the cell isn't
                            // available, so the gameplay guard is enough.
                        }
                    }
                }
            }

            // The # grid: two horizontals + two verticals, drawn over the
            // cells so the lines clearly separate the squares without
            // boxing them in.
            WOPRGrid()
                .stroke(crtCyan, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .shadow(color: crtCyan.opacity(0.7), radius: 5)
                .frame(width: 330, height: 330)
                .allowsHitTesting(false)
        }
    }

    /// Monologue typed one character at a time with a blinking block
    /// cursor. Layout stability comes from an *invisible* full-text
    /// reservation underneath the visible typed-so-far text — that locks
    /// the multi-line box at its final dimensions so growing the visible
    /// string can't reflow it. The padded-spaces approach we used before
    /// hit SwiftUI's trailing-whitespace stripping and made each line's
    /// rendered width creep as more characters were typed.
    private var monologueView: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ZStack(alignment: .topLeading) {
                    // Append a trailing `_` so the reservation's last line
                    // includes a cursor's worth of width. Without it, the
                    // visible text grows 1 monospace char wider when the
                    // blink cursor renders, and the centered HStack shifts.
                    Text(monologue + "_")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.clear)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: true, vertical: true)
                    TimelineView(.periodic(from: Date(), by: 0.25)) { context in
                        Text(typedSoFar(at: context.date))
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(crtCyan)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: true, vertical: true)
                            .shadow(color: crtCyan.opacity(0.75), radius: 6)
                    }
                }
                Spacer()
            }
            Spacer()
        }
        .onAppear {
            startTyping()
        }
        .onDisappear {
            typeTimer?.invalidate()
            typeTimer = nil
            speechSynth?.stopSpeaking()
            speechSynth = nil
            speechDelegate = nil
        }
    }

    private func typedSoFar(at date: Date) -> String {
        let chars = Array(monologue)
        let n = min(typedCount, chars.count)
        let blink = Int(date.timeIntervalSinceReferenceDate * 2) % 2 == 0
        // Always append one char so the visible width is constant —
        // monospace `_` and ` ` are the same advance width, so toggling
        // them on blink doesn't shift the centered text block.
        return String(chars.prefix(n)) + (blink ? "_" : " ")
    }

    private func startTyping() {
        typedCount = 0
        typeResumeAt = nil
        typeTimer?.invalidate()
        startNarration()
        let chars = Array(monologue)
        typeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { t in
            DispatchQueue.main.async {
                // Honor any active paragraph-break hold.
                if let resumeAt = typeResumeAt, Date() < resumeAt {
                    return
                }
                if typedCount >= chars.count {
                    t.invalidate()
                    // Backup dismiss: 3s after typing finishes. The
                    // narration delegate's 3s-delayed dismiss usually
                    // wins; this fires when the voice isn't installed.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        TicTacToeGame.dismiss()
                    }
                    return
                }
                typedCount += 1
                // After typing the second `\n` of a paragraph break,
                // hold for 700ms — matches the narration's
                // `[[slnc 700]]` beat 1:1.
                if typedCount >= 2,
                   chars[typedCount - 1] == "\n",
                   chars[typedCount - 2] == "\n" {
                    typeResumeAt = Date().addingTimeInterval(0.7)
                }
            }
        }
    }

    /// Speak the monologue in the classic Junior robotic voice. Falls
    /// back to the system default if Junior isn't installed. A 700ms
    /// silence command is injected where the source has a blank line so
    /// the narration takes the same dramatic beat the typewriter does
    /// before "HOW ABOUT…".
    private func startNarration() {
        let juniorID = NSSpeechSynthesizer.VoiceName(rawValue: "com.apple.speech.synthesis.voice.Junior")
        let synth = NSSpeechSynthesizer(voice: juniorID) ?? NSSpeechSynthesizer()
        // Roughly match the on-screen typing speed.
        synth.rate = 230
        let delegate = SpeechDelegate {
            // Hold for 3s after the last syllable so the line lingers
            // on screen before the window goes away.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                TicTacToeGame.dismiss()
            }
        }
        synth.delegate = delegate
        // Convert the blank-line gap to an explicit 700ms silence; flatten
        // remaining single newlines so the synth doesn't pause forever.
        let spoken = monologue
            .replacingOccurrences(of: "\n\n", with: " [[slnc 700]] ")
            .replacingOccurrences(of: "\n", with: " ")
        synth.startSpeaking(spoken)
        speechSynth = synth
        speechDelegate = delegate
    }

    private func play(_ idx: Int) {
        guard board[idx] == .empty, humanTurn, !done else { return }
        board[idx] = .x
        TicTacToeSounds.boop()
        if checkEnd(player: .x) { return }
        humanTurn = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            MainActor.assumeIsolated {
                guard !done else { return }
                let m = bestMove(for: .o)
                board[m] = .o
                TicTacToeSounds.beep()
                _ = checkEnd(player: .o)
                humanTurn = true
            }
        }
    }

    /// Wipe the board back to its initial state. Called after the CPU
    /// wins, so the user can immediately try again without hunting for
    /// a button. Doesn't touch monologue/typing state — that path is
    /// reserved for stalemate.
    private func resetBoard() {
        withAnimation(.easeInOut(duration: 0.25)) {
            board = Array(repeating: .empty, count: 9)
            status = "SHALL WE PLAY A GAME?"
            humanTurn = true
            done = false
        }
    }

    /// Minimax over the remaining game tree. With perfect play from both
    /// sides tic-tac-toe is always a draw — and since the human can play
    /// suboptimally, the CPU will *take* the win when offered. Best case
    /// for the user is therefore a draw, never a win.
    private func bestMove(for player: Mark) -> Int {
        var bestIdx = -1
        var bestScore = Int.min
        for i in 0..<9 where board[i] == .empty {
            var b = board
            b[i] = player
            let s = minimax(b, depth: 0, isMaximizing: false, player: player)
            if s > bestScore {
                bestScore = s
                bestIdx = i
            }
        }
        return bestIdx
    }

    private func minimax(_ b: [Mark], depth: Int, isMaximizing: Bool, player: Mark) -> Int {
        let opponent: Mark = player == .o ? .x : .o
        if wins(b, player) { return 10 - depth }
        if wins(b, opponent) { return depth - 10 }
        if !b.contains(.empty) { return 0 }

        if isMaximizing {
            var best = Int.min
            for i in 0..<9 where b[i] == .empty {
                var next = b
                next[i] = player
                best = max(best, minimax(next, depth: depth + 1, isMaximizing: false, player: player))
            }
            return best
        } else {
            var best = Int.max
            for i in 0..<9 where b[i] == .empty {
                var next = b
                next[i] = opponent
                best = min(best, minimax(next, depth: depth + 1, isMaximizing: true, player: player))
            }
            return best
        }
    }

    private func wins(_ b: [Mark], _ player: Mark) -> Bool {
        winningLines.contains { line in line.allSatisfy { b[$0] == player } }
    }

    @discardableResult
    private func checkEnd(player: Mark) -> Bool {
        if wins(board, player) {
            status = player == .x ? "IMPOSSIBLE." : "GAME OVER."
            done = true
            // Player just lost — auto-reset after a beat so they can
            // try again without hunting for a button.
            if player == .o {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    MainActor.assumeIsolated { resetBoard() }
                }
            }
            return true
        }
        if !board.contains(.empty) {
            done = true
            // Stalemate jumps straight to Joshua's monologue — that's
            // the moment in the film when WOPR figures it out. Skip
            // any "STALEMATE." status text; the closing scene is the
            // payoff.
            scheduleMonologue()
            return true
        }
        return false
    }

    /// After the game ends, give the user a brief beat to see the final
    /// move land, then clear the board and type out Joshua's monologue.
    private func scheduleMonologue() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            MainActor.assumeIsolated {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showMonologue = true
                }
            }
        }
    }

    private let winningLines: [[Int]] = [
        [0, 1, 2], [3, 4, 5], [6, 7, 8],
        [0, 3, 6], [1, 4, 7], [2, 5, 8],
        [0, 4, 8], [2, 4, 6]
    ]

}

/// Pair of short sine-wave tones played on each move. Generated in code
/// (a small WAV-encoded sine with a 5ms fade in/out to avoid clicks) so
/// we don't have to bundle audio assets for two ~80ms beeps. `boop` (low)
/// fires on the player's X, `beep` (high) on the CPU's O.
@MainActor
enum TicTacToeSounds {
    private static let xPlayer: AVAudioPlayer? = makePlayer(frequency: 280, duration: 0.08)
    private static let oPlayer: AVAudioPlayer? = makePlayer(frequency: 560, duration: 0.08)

    static func boop() { trigger(xPlayer) }
    static func beep() { trigger(oPlayer) }

    private static func trigger(_ p: AVAudioPlayer?) {
        guard let p = p else { return }
        p.stop()
        p.currentTime = 0
        p.play()
    }

    private static func makePlayer(frequency: Double, duration: Double) -> AVAudioPlayer? {
        let data = makeWaveData(frequency: frequency, duration: duration)
        guard let p = try? AVAudioPlayer(data: data) else { return nil }
        p.volume = 0.35
        p.prepareToPlay()
        return p
    }

    /// Build a minimal mono 16-bit PCM WAV file containing `duration`
    /// seconds of a `frequency` Hz sine wave, with a short triangular
    /// envelope to avoid pops on attack/release.
    private static func makeWaveData(frequency: Double, duration: Double) -> Data {
        let sampleRate: Double = 44100
        let numSamples = Int(duration * sampleRate)
        let fadeSamples = min(numSamples / 8, Int(0.005 * sampleRate))
        let amplitude = Double(Int16.max) * 0.6

        var samples = [Int16]()
        samples.reserveCapacity(numSamples)
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let sine = sin(2 * .pi * frequency * t)
            var env: Double = 1.0
            if i < fadeSamples {
                env = Double(i) / Double(fadeSamples)
            } else if i > numSamples - fadeSamples {
                env = Double(numSamples - i) / Double(fadeSamples)
            }
            samples.append(Int16(amplitude * sine * env))
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
        writeUInt16LE(1)               // PCM
        writeUInt16LE(1)               // mono
        writeUInt32LE(UInt32(sampleRate))
        writeUInt32LE(UInt32(sampleRate) * 2)
        writeUInt16LE(2)               // block align (bytes/sample × channels)
        writeUInt16LE(16)              // bits per sample
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

/// Delegate that fires a callback when Fred finishes the monologue. The
/// view stores an instance in `@State` so it survives long enough for
/// `NSSpeechSynthesizer` (which holds the delegate weakly) to call it.
@MainActor
private final class SpeechDelegate: NSObject, NSSpeechSynthesizerDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    nonisolated func speechSynthesizer(_ sender: NSSpeechSynthesizer,
                                       didFinishSpeaking finishedSpeaking: Bool) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.onFinish() }
        }
    }
}

/// The X mark — two diagonal lines across the cell, drawn as a Shape so
/// we can stroke it with the same thick CRT-cyan style as the O.
private struct WOPRMarkX: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}

/// The `#` grid — two horizontals + two verticals across a square frame.
/// Drawn as freestanding lines (no outer border) to match the WarGames
/// display.
private struct WOPRGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let third = rect.width / 3
        let twoThirds = third * 2
        // Vertical lines.
        p.move(to: CGPoint(x: rect.minX + third, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + third, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + twoThirds, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + twoThirds, y: rect.maxY))
        // Horizontal lines.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + third))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + third))
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + twoThirds))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + twoThirds))
        return p
    }
}
