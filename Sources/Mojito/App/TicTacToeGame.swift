import AppKit
import AVFoundation
import SwiftUI

/// WarGames Tic-Tac-Toe. CPU runs full minimax — best case is a draw,
/// which triggers Joshua's "A STRANGE GAME…" monologue.
@MainActor
enum TicTacToeGame {
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    static func dismiss() {
        window?.close()
    }

    static func start() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Width fits the widest monologue line at 22pt mono + tracking 2.
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
    /// Hides the board and shows the typewriter monologue.
    @State private var showMonologue = false
    @State private var typedCount: Int = 0
    @State private var typeTimer: Timer?
    @State private var sayTask: Process?
    /// Set at each `\n\n` so the on-screen pause matches the narration's
    /// `[[slnc …]]` beat.
    @State private var typeResumeAt: Date?

    /// Glowing WOPR-screen cyan from the film.
    private let crtCyan = Color(red: 0.55, green: 0.92, blue: 1.0)
    private let crtCyanDim = Color(red: 0.35, green: 0.62, blue: 0.78)
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

    /// `#`-shape grid — no cell borders, no outer frame. Marks are
    /// stroked shapes for the chunky vector-CRT look.
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
                            // No `.disabled` — it dims the placed mark
                            // paler than the grid lines. `play(_:)` already
                            // guards against double-placement.
                        }
                    }
                }
            }

            WOPRGrid()
                .stroke(crtCyan, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .shadow(color: crtCyan.opacity(0.7), radius: 5)
                .frame(width: 330, height: 330)
                .allowsHitTesting(false)
        }
    }

    /// Layout stability via an invisible full-text reservation
    /// underneath the visible typed-so-far text — locks dimensions so
    /// growing the visible string can't reflow it.
    private var monologueView: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ZStack(alignment: .topLeading) {
                    // Trailing `_` reserves a cursor's worth of width so
                    // the visible text doesn't shift when the blink renders.
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
            sayTask?.terminate()
            sayTask = nil
        }
    }

    private func typedSoFar(at date: Date) -> String {
        let chars = Array(monologue)
        let n = min(typedCount, chars.count)
        let blink = Int(date.timeIntervalSinceReferenceDate * 2) % 2 == 0
        // Mono `_` and ` ` share advance width, so blinking doesn't shift
        // the centered block.
        return String(chars.prefix(n)) + (blink ? "_" : " ")
    }

    private func startTyping() {
        typedCount = 0
        typeResumeAt = nil
        typeTimer?.invalidate()
        startNarration()
        let chars = Array(monologue)
        // 0.085s/char keeps the typewriter roughly in sync with Fred at
        // his default ~175 wpm pace; the 700ms pause below mirrors
        // `[[slnc 700]]` so the mid-monologue beat lines up.
        typeTimer = Timer.scheduledTimer(withTimeInterval: 0.085, repeats: true) { t in
            DispatchQueue.main.async {
                if let resumeAt = typeResumeAt, Date() < resumeAt {
                    return
                }
                if typedCount >= chars.count {
                    t.invalidate()
                    // Backup dismiss for when the voice isn't installed;
                    // otherwise the narration delegate dismisses first.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        TicTacToeGame.dismiss()
                    }
                    return
                }
                typedCount += 1
                // Hold 700ms at a `\n\n` to match `[[slnc 700]]`.
                if typedCount >= 2,
                   chars[typedCount - 1] == "\n",
                   chars[typedCount - 2] == "\n" {
                    typeResumeAt = Date().addingTimeInterval(0.7)
                }
            }
        }
    }

    /// Speaks the monologue via `/usr/bin/say -v Fred`, matching the
    /// donation thank-you. No `-r` override so Fred speaks at his default
    /// ~175 wpm — the WOPR monologue lands better at a measured pace than
    /// at the donation's clipped 300 wpm. `[[slnc 700]]` injects the
    /// mid-monologue beat. `terminationHandler` fires when `say` exits
    /// (or is terminated on dismiss), so we linger 3s after the last
    /// syllable like before.
    private func startNarration() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        let line = monologue
            .replacingOccurrences(of: "\n\n", with: " [[slnc 700]] ")
            .replacingOccurrences(of: "\n", with: " ")
        task.arguments = ["-v", "Fred", line]
        task.terminationHandler = { proc in
            // `terminate()` on dismiss sends SIGTERM (non-zero status);
            // skip the linger-and-dismiss in that case — we're already
            // tearing down.
            guard proc.terminationStatus == 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                MainActor.assumeIsolated { TicTacToeGame.dismiss() }
            }
        }
        do {
            try task.run()
            sayTask = task
        } catch {
            // Voice unavailable: typewriter timer dismisses the window
            // after its own 3s linger (see startTyping).
        }
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

    /// Called after a CPU win so the user can try again. Stalemate
    /// goes to the monologue path instead.
    private func resetBoard() {
        withAnimation(.easeInOut(duration: 0.25)) {
            board = Array(repeating: .empty, count: 9)
            status = "SHALL WE PLAY A GAME?"
            humanTurn = true
            done = false
        }
    }

    /// Minimax: perfect play draws, suboptimal play loses. Never wins.
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
            if player == .o {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    MainActor.assumeIsolated { resetBoard() }
                }
            }
            return true
        }
        if !board.contains(.empty) {
            done = true
            // Stalemate goes straight to the monologue — the closing
            // scene is the payoff. No "STALEMATE." status.
            scheduleMonologue()
            return true
        }
        return false
    }

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

/// In-code sine pair (5ms fades, no clicks): `boop` low for X,
/// `beep` high for O. Saves bundling two 80ms WAVs.
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

    /// Mono 16-bit PCM WAV: `frequency` Hz sine, triangular envelope
    /// to avoid attack/release pops.
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

/// Shape so it strokes with the same CRT-cyan style as the O.
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

/// Freestanding `#` — two horizontals + two verticals, no outer border.
private struct WOPRGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let third = rect.width / 3
        let twoThirds = third * 2
        p.move(to: CGPoint(x: rect.minX + third, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + third, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + twoThirds, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + twoThirds, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + third))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + third))
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + twoThirds))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + twoThirds))
        return p
    }
}
