import AppKit
import SwiftUI

/// Full-screen retro disk-optimizer "screen saver": a grid of cluster
/// blocks that consolidates fragmented data toward the front while the
/// read/write head darts around to fetch scattered clusters. The whole
/// run is pre-computed at trigger time as an ordered list of relocations,
/// so the renderer is a pure function of elapsed time. Auto-dismisses
/// when the run finishes (or on Esc via `EffectDismisser`).
@MainActor
enum DiskOptimizer {
    private static var activeWindow: NSWindow?
    private static var activeDismiss: (() -> Void)?

    static func start() {
        // Tear down any in-flight run first so the shared sound singleton
        // isn't left orphaned across a re-trigger.
        activeDismiss?()

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        let script = OptimizerRun(width: frame.width, height: frame.height)

        let panel = ParticlePanel.makeFullScreen(frame: frame)
        let host = NSHostingView(rootView: OptimizerView(
            script: script,
            startDate: Date(),
            bounds: frame.size
        ))
        host.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = host
        panel.orderFrontRegardless()
        activeWindow = panel

        DiskChatterSound.start()

        var cancelToken: (() -> Void)?
        let dismiss = {
            MainActor.assumeIsolated {
                // A stale auto-dismiss timer from a superseded run must not
                // stop the current run's shared sound — bail unless this
                // dismiss still owns the active window.
                guard activeWindow === panel else { return }
                DiskChatterSound.stop()
                panel.orderOut(nil)
                cancelToken?(); cancelToken = nil
                activeWindow = nil
                activeDismiss = nil
            }
        }
        cancelToken = EffectDismisser.register(dismiss)
        activeDismiss = dismiss

        // Hold the optimized grid for a beat after the last move lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + script.totalDuration + 1.6) {
            MainActor.assumeIsolated { dismiss() }
        }
    }
}

// MARK: - Simulation

private enum CellState: UInt8 {
    case free        // unused cluster
    case fragmented  // used data, not yet consolidated
    case data        // used data, settled at the front
    case system      // unmovable system cluster (never moves)
    case reading     // source of the in-flight relocation
    case writing     // destination of the in-flight relocation
}

/// Pre-computed run. `initial` is the starting grid; `moves` are the
/// relocations in time order. The view replays them against elapsed time.
private struct OptimizerRun {
    let cols: Int
    let rows: Int
    let cellSize: CGFloat
    let originX: CGFloat
    let originY: CGFloat
    let systemCount: Int
    let finalBoundary: Int   // first free index once optimized
    let initial: [CellState]
    let moves: [Move]
    let totalDuration: TimeInterval

    struct Move {
        let from: Int
        let to: Int
        let start: TimeInterval
        let duration: TimeInterval
    }

    init(width: CGFloat, height: CGFloat) {
        // ~80 columns reads as a dense cluster map without thousands of cells.
        let targetCols = 80
        let cols = max(40, min(targetCols, Int(width / 16)))
        let cellSize = (width / CGFloat(cols)).rounded(.down)
        let rows = max(20, Int(height / cellSize))
        let n = cols * rows

        self.cols = cols
        self.rows = rows
        self.cellSize = cellSize
        self.originX = (width - CGFloat(cols) * cellSize) / 2
        self.originY = (height - CGFloat(rows) * cellSize) / 2

        // A handful of unmovable system clusters pinned at the very front.
        let systemCount = max(6, n / 220)
        self.systemCount = systemCount

        // ~58% of the disk is "in use"; the rest is free space.
        let usedCount = Int(Double(n) * 0.58)
        let finalBoundary = min(n, systemCount + usedCount)
        self.finalBoundary = finalBoundary

        // Number of clusters that have to be relocated. Capped so the run
        // lands around ~38s rather than scaling with the screen.
        let frontSpan = finalBoundary - systemCount
        let relocations = max(40, min(300, frontSpan / 4))

        // Lay out the starting grid: `usedInFront` settled-but-scattered
        // clusters live in the front span (leaving `relocations` gaps), and
        // exactly `relocations` clusters are flung out into the tail so each
        // one must be pulled back.
        var grid = [CellState](repeating: .free, count: n)
        for i in 0..<systemCount { grid[i] = .system }

        let usedInFront = max(0, frontSpan - relocations)
        var frontSlots = Array(systemCount..<finalBoundary)
        frontSlots.shuffle()
        for i in 0..<min(usedInFront, frontSlots.count) {
            grid[frontSlots[i]] = .fragmented
        }

        let tailRange = finalBoundary..<n
        if !tailRange.isEmpty {
            var tailSlots = Array(tailRange)
            tailSlots.shuffle()
            for i in 0..<min(relocations, tailSlots.count) {
                grid[tailSlots[i]] = .fragmented
            }
        }

        // Walk a write pointer forward, pulling the next used cluster down
        // into each gap. Each pull is one timed relocation.
        var moves: [Move] = []
        moves.reserveCapacity(relocations)
        var sim = grid
        var writePtr = systemCount
        var t: TimeInterval = 0
        var readPtr = finalBoundary   // tail clusters live at or past here

        while writePtr < finalBoundary {
            if sim[writePtr] != .free {
                writePtr += 1
                continue
            }
            // Next used cluster in the tail.
            while readPtr < n && sim[readPtr] != .fragmented { readPtr += 1 }
            if readPtr >= n { break }

            // Longer seeks (further reads) chatter a touch longer.
            let seek = readPtr - writePtr
            let duration = 0.06 + min(0.05, Double(seek) / Double(max(1, n)) * 0.4)
            moves.append(Move(from: readPtr, to: writePtr, start: t, duration: duration))

            // Occasional longer pause — the "…chk … chk chk" cadence.
            let gap = (Int.random(in: 0..<9) == 0) ? Double.random(in: 0.30...0.55)
                                                   : Double.random(in: 0.02...0.07)
            t += duration + gap

            sim[writePtr] = .data
            sim[readPtr] = .free
            writePtr += 1
            readPtr += 1
        }

        self.initial = grid
        self.moves = moves
        self.totalDuration = t
    }
}

// MARK: - Rendering

private struct OptimizerView: View {
    let script: OptimizerRun
    let startDate: Date
    let bounds: CGSize

    // Classic 9x optimizer palette.
    private let gridLine  = Color(white: 0.78)
    private let freeColor = Color.white
    private let fragColor = Color(red: 0.56, green: 0.71, blue: 0.95)   // pale blue
    private let dataColor = Color(red: 0.11, green: 0.31, blue: 0.76)   // solid blue
    private let sysColor  = Color(red: 0.0,  green: 0.55, blue: 0.0)    // green
    private let readColor = Color(red: 0.90, green: 0.10, blue: 0.10)   // red head
    private let writeColor = Color(red: 1.0, green: 0.85, blue: 0.0)    // yellow head

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            Canvas { ctx, size in
                draw(ctx: &ctx, size: size, elapsed: elapsed)
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .ignoresSafeArea()
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let cols = script.cols
        let rows = script.rows
        let n = cols * rows
        let cell = script.cellSize

        // Grid background (becomes the thin separators between clusters).
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(gridLine))

        // Replay completed moves onto a working copy of the initial grid.
        var state = script.initial
        var writeFront = script.systemCount - 1
        var active: OptimizerRun.Move?
        for move in script.moves {
            let end = move.start + move.duration
            if end <= elapsed {
                state[move.to] = .data
                state[move.from] = .free
                writeFront = max(writeFront, move.to)
            } else if move.start <= elapsed {
                active = move
                break
            } else {
                break
            }
        }

        // Anything settled (system, or used at/behind the write front) reads
        // as optimized; used clusters still ahead read as fragmented.
        for i in script.systemCount..<n where state[i] != .free {
            state[i] = (i <= writeFront) ? .data : .fragmented
        }

        if let active {
            state[active.from] = .reading
            state[active.to] = .writing
        }

        // Batch one fill per colour.
        let gap: CGFloat = cell >= 12 ? 0.75 : 0.4
        var paths: [CellState: Path] = [:]
        for i in 0..<n {
            let st = state[i]
            if st == .free { continue }   // free == white == grid background tone
            let col = i % cols
            let row = i / cols
            let rect = CGRect(
                x: script.originX + CGFloat(col) * cell + gap,
                y: script.originY + CGFloat(row) * cell + gap,
                width: cell - gap * 2,
                height: cell - gap * 2
            )
            paths[st, default: Path()].addRect(rect)
        }
        // Free cells: paint them white over the grey background so the grid
        // lines show only as separators.
        var freePath = Path()
        for i in 0..<n where state[i] == .free {
            let col = i % cols
            let row = i / cols
            freePath.addRect(CGRect(
                x: script.originX + CGFloat(col) * cell + gap,
                y: script.originY + CGFloat(row) * cell + gap,
                width: cell - gap * 2,
                height: cell - gap * 2
            ))
        }
        ctx.fill(freePath, with: .color(freeColor))

        for (st, path) in paths {
            ctx.fill(path, with: .color(color(for: st)))
        }

        drawStatus(ctx: &ctx, size: size, writeFront: writeFront)
    }

    private func color(for state: CellState) -> Color {
        switch state {
        case .free:       return freeColor
        case .fragmented: return fragColor
        case .data:       return dataColor
        case .system:     return sysColor
        case .reading:    return readColor
        case .writing:    return writeColor
        }
    }

    private func drawStatus(ctx: inout GraphicsContext, size: CGSize, writeFront: Int) {
        let span = max(1, script.finalBoundary - script.systemCount)
        let done = max(0, writeFront - script.systemCount + 1)
        let pct = min(100, Int(Double(done) / Double(span) * 100))

        let label = "Optimizing Drive (C:) — \(pct)% Complete"
        let resolved = ctx.resolve(
            Text(verbatim: label)
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundColor(Color(white: 0.1))
        )
        let textSize = resolved.measure(in: size)
        let pad: CGFloat = 14
        let boxW = textSize.width + pad * 2
        let boxH = textSize.height + pad
        let box = CGRect(
            x: (size.width - boxW) / 2,
            y: size.height - boxH - 28,
            width: boxW,
            height: boxH
        )
        ctx.fill(
            Path(roundedRect: box, cornerRadius: 4),
            with: .color(Color(white: 0.86))
        )
        ctx.stroke(
            Path(roundedRect: box, cornerRadius: 4),
            with: .color(Color(white: 0.55)),
            lineWidth: 1
        )
        ctx.draw(resolved, at: CGPoint(x: box.midX, y: box.midY))
    }
}
