import AppKit
import SwiftUI

/// Classic Snake in a regular game window. Triggered by the keyword.
///
/// Arrow keys steer; Esc quits. Key handling lives on a custom NSWindow
/// subclass — SwiftUI's NSHostingView doesn't put a child responder into
/// the chain reliably, and global/local NSEvent monitors are unreliable
/// for LSUIElement apps. Overriding `keyDown` on the window itself works
/// because unhandled keys bubble up the responder chain and the window is
/// the last stop.
///
/// Visual treatment is delightful instead of utilitarian: emoji snake
/// (head distinct from body), apple food, retro arcade-style scoreboard,
/// and a custom green border + title bar.
@MainActor
enum SnakeGame {
    fileprivate static var window: SnakeWindow?
    private static var closeObserver: NSObjectProtocol?
    fileprivate static let model = SnakeModel()

    static func start() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        model.reset()

        let size = NSSize(width: 480, height: 600)
        let w = SnakeWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = ""
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = NSColor(red: 0.02, green: 0.05, blue: 0.02, alpha: 1)
        w.appearance = NSAppearance(named: .darkAqua)
        w.isReleasedWhenClosed = false
        w.center()
        w.level = .floating

        let host = NSHostingView(rootView: SnakeGameView(model: model))
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

/// NSWindow subclass that intercepts key events for Snake. Arrow keys steer;
/// Esc closes the window. Other keys are ignored — we used to bail on any
/// non-arrow key, but the synthetic backspace burst from the the keyword
/// shortcode deletion arrives at this window once it becomes key, which
/// instantly closed the game before the user saw anything.
fileprivate final class SnakeWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        let model = SnakeGame.model
        switch Int(event.keyCode) {
        case 126: model.turn(.up)
        case 125: model.turn(.down)
        case 123: model.turn(.left)
        case 124: model.turn(.right)
        case 49:  model.togglePauseOrRestart()  // Space
        case 53:  self.close()   // Esc
        default:  break
        }
    }
}

private struct Point: Equatable {
    var x: Int
    var y: Int
}

fileprivate enum Direction {
    case up, down, left, right
    var dx: Int { self == .left ? -1 : self == .right ? 1 : 0 }
    var dy: Int { self == .up ? -1 : self == .down ? 1 : 0 }
    func isOpposite(of other: Direction) -> Bool {
        (self == .up && other == .down) || (self == .down && other == .up) ||
        (self == .left && other == .right) || (self == .right && other == .left)
    }
}

@MainActor
fileprivate final class SnakeModel: ObservableObject {
    static let gridSize = 20

    @Published var snake: [Point] = []
    @Published var direction: Direction = .right
    @Published var food: Point = Point(x: 15, y: 10)
    @Published var score: Int = 0
    @Published var highScore: Int = UserDefaults.standard.integer(forKey: "snake.highScore")
    @Published var gameOver = false
    @Published var paused = false

    private var nextDirection: Direction = .right

    init() { reset() }

    func reset() {
        snake = [Point(x: 10, y: 10), Point(x: 9, y: 10), Point(x: 8, y: 10)]
        direction = .right
        nextDirection = .right
        food = Point(x: 15, y: 10)
        score = 0
        gameOver = false
        paused = false
    }

    func turn(_ d: Direction) {
        if d.isOpposite(of: direction) { return }
        nextDirection = d
    }

    func togglePauseOrRestart() {
        if gameOver { reset(); return }
        paused.toggle()
    }

    func tick() {
        guard !gameOver, !paused else { return }
        direction = nextDirection
        guard let head = snake.first else { return }
        var next = Point(x: head.x + direction.dx, y: head.y + direction.dy)
        if next.x < 0 { next.x = Self.gridSize - 1 }
        if next.x >= Self.gridSize { next.x = 0 }
        if next.y < 0 { next.y = Self.gridSize - 1 }
        if next.y >= Self.gridSize { next.y = 0 }

        if snake.contains(next) {
            gameOver = true
            if score > highScore {
                highScore = score
                UserDefaults.standard.set(highScore, forKey: "snake.highScore")
            }
            return
        }

        snake.insert(next, at: 0)
        if next == food {
            score += 1
            food = randomFood()
        } else {
            snake.removeLast()
        }
    }

    private func randomFood() -> Point {
        while true {
            let p = Point(x: Int.random(in: 0..<Self.gridSize), y: Int.random(in: 0..<Self.gridSize))
            if !snake.contains(p) { return p }
        }
    }
}

private struct SnakeGameView: View {
    @ObservedObject var model: SnakeModel

    private let cellSize: CGFloat = 22
    private let tickInterval: TimeInterval = 0.11

    /// Phosphor-green palette — feels like a vintage arcade cabinet.
    private let bg = Color(red: 0.02, green: 0.05, blue: 0.02)
    private let panel = Color(red: 0.06, green: 0.12, blue: 0.06)
    private let phosphor = Color(red: 0.55, green: 1.0, blue: 0.55)
    private let phosphorDim = Color(red: 0.35, green: 0.7, blue: 0.4)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            VStack(spacing: 14) {
                titleBar
                scoreBar
                boardFrame
                hintBar
            }
            .padding(16)
        }
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Text("🐍")
                .font(.system(size: 24))
            Text("SNAKE")
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .foregroundColor(phosphor)
                .tracking(8)
                .shadow(color: phosphor.opacity(0.7), radius: 5)
        }
        .padding(.top, 6)
    }

    private var scoreBar: some View {
        HStack(spacing: 12) {
            scoreCell(label: "SCORE", value: model.score)
            Spacer()
            statePill
            Spacer()
            scoreCell(label: "BEST", value: model.highScore)
        }
        .padding(.horizontal, 6)
    }

    private func scoreCell(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(phosphorDim)
                .tracking(3)
            Text(String(format: "%04d", value))
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .foregroundColor(phosphor)
                .shadow(color: phosphor.opacity(0.55), radius: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(panel)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(phosphor.opacity(0.5), lineWidth: 1)
        )
    }

    private var statePill: some View {
        Group {
            if model.gameOver {
                Text("GAME OVER")
                    .foregroundColor(Color.red)
                    .shadow(color: .red.opacity(0.7), radius: 5)
            } else if model.paused {
                Text("PAUSED")
                    .foregroundColor(.yellow)
            } else {
                Text("PLAYING")
                    .foregroundColor(phosphorDim)
            }
        }
        .font(.system(size: 12, weight: .heavy, design: .monospaced))
        .tracking(4)
    }

    private var boardFrame: some View {
        TimelineView(.animation(minimumInterval: tickInterval, paused: model.gameOver || model.paused)) { context in
            let _ = context.date
            board
                .onChange(of: context.date) { _, _ in
                    model.tick()
                }
        }
        .frame(width: cellSize * CGFloat(SnakeModel.gridSize),
               height: cellSize * CGFloat(SnakeModel.gridSize))
        .padding(6)
        .background(panel)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(phosphor, lineWidth: 2)
                .shadow(color: phosphor.opacity(0.5), radius: 6)
        )
    }

    private var hintBar: some View {
        Text("← ↑ ↓ →  steer    SPACE  pause / restart    ESC  quit")
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundColor(phosphorDim)
            .tracking(1)
            .padding(.bottom, 4)
    }

    /// Board renderer. Snake body uses 🟢, head is 🐲 (more distinct than
    /// 🐍 at this size and reads as a "snake head"), food is 🍎. Drawing
    /// emoji via `ctx.draw(ctx.resolve(Text(…)))` is cheap enough at 20x20
    /// to stay smooth — and means we don't need any image assets.
    private var board: some View {
        Canvas { ctx, size in
            // Subtle grid lines so the field looks game-like instead of
            // a blank well.
            let gridColor = Color(white: 1.0, opacity: 0.04)
            for i in 0...SnakeModel.gridSize {
                let x = CGFloat(i) * cellSize
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(gridColor),
                    lineWidth: 0.5
                )
                let y = CGFloat(i) * cellSize
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    },
                    with: .color(gridColor),
                    lineWidth: 0.5
                )
            }

            // Food.
            drawEmoji(in: ctx, "🍎", at: model.food, size: cellSize * 0.95)

            // Snake — head first, then body segments. Head is a dragon
            // face so it visibly differs from the round body cells.
            for (i, seg) in model.snake.enumerated() {
                let glyph = i == 0 ? "🐲" : "🟢"
                drawEmoji(in: ctx, glyph, at: seg, size: cellSize * 0.95)
            }

            // Overlay messages.
            if model.gameOver {
                drawCenteredLabel(in: ctx, text: "GAME OVER", subtitle: "SPACE to restart", boardSize: size)
            } else if model.paused {
                drawCenteredLabel(in: ctx, text: "PAUSED", subtitle: "SPACE to resume", boardSize: size)
            }
        }
    }

    private func drawEmoji(in ctx: GraphicsContext, _ glyph: String, at p: Point, size s: CGFloat) {
        let t = Text(glyph).font(.system(size: s))
        let resolved = ctx.resolve(t)
        let cx = CGFloat(p.x) * cellSize + cellSize / 2
        let cy = CGFloat(p.y) * cellSize + cellSize / 2
        ctx.draw(resolved, at: CGPoint(x: cx, y: cy), anchor: .center)
    }

    private func drawCenteredLabel(in ctx: GraphicsContext, text: String, subtitle: String, boardSize: CGSize) {
        // Dim the playfield behind the overlay.
        ctx.fill(
            Path(CGRect(origin: .zero, size: boardSize)),
            with: .color(.black.opacity(0.55))
        )
        let title = Text(text)
            .font(.system(size: 36, weight: .black, design: .monospaced))
            .foregroundColor(.white)
        let resolvedTitle = ctx.resolve(title)
        let titleSize = resolvedTitle.measure(in: boardSize)
        ctx.draw(
            resolvedTitle,
            at: CGPoint(x: boardSize.width / 2,
                        y: boardSize.height / 2 - titleSize.height / 2),
            anchor: .center
        )
        let sub = Text(subtitle)
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .foregroundColor(.white.opacity(0.85))
        let resolvedSub = ctx.resolve(sub)
        ctx.draw(
            resolvedSub,
            at: CGPoint(x: boardSize.width / 2,
                        y: boardSize.height / 2 + titleSize.height / 2 + 6),
            anchor: .center
        )
    }
}
