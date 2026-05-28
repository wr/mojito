import AppKit
import SwiftUI

/// Full-screen retro disk-optimizer "screen saver": the classic 9x defrag
/// dialog on a teal desktop. A head sweeps the fragmented cluster map
/// left-to-right; each front gap it fills pulls a cluster from the end of the
/// disk, so tail fragments vanish as the front goes contiguous — mostly a few
/// at a time, occasionally a big band. The run is pre-computed at trigger time,
/// so both the renderer and the disk-chatter are pure functions of the same
/// (paused-adjusted) elapsed clock. Dismisses when finished, on Esc, or Stop.
@MainActor
enum DiskOptimizer {
    private static var activeWindow: NSWindow?
    private static var activeDismiss: (() -> Void)?

    static func start() {
        activeDismiss?()

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        // Fixed window size (clamped to fit) so the dialog doesn't scale up on
        // large / 4K displays — its chrome, fonts, and blocks are point-sized.
        let winW = min(1040, frame.width - 80)
        let winH = min(640, frame.height - 80)
        let script = OptimizerRun(width: winW * 0.94, height: winH * 0.56)

        let panel = ParticlePanel.makeFullScreen(frame: frame, interactive: true)
        activeWindow = panel

        var cancelToken: (() -> Void)?
        let dismiss = {
            MainActor.assumeIsolated {
                guard activeWindow === panel else { return }
                DiskChatterSound.stop()
                panel.contentView = nil   // drop the hosting view so its timeline stops
                panel.orderOut(nil)
                cancelToken?(); cancelToken = nil
                activeWindow = nil
                activeDismiss = nil
            }
        }

        let host = NSHostingView(rootView: DefragWindowView(
            script: script,
            startDate: Date(),
            screenSize: frame.size,
            windowSize: CGSize(width: winW, height: winH),
            onStop: { dismiss() }
        ))
        host.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = host
        panel.orderFrontRegardless()

        DiskChatterSound.start()

        cancelToken = EffectDismisser.register(dismiss)
        activeDismiss = dismiss

        // Payoff for sitting through the whole defrag: a Ta-da on completion,
        // then hold the optimized grid a beat before auto-dismissing.
        DispatchQueue.main.asyncAfter(deadline: .now() + script.totalDuration) {
            MainActor.assumeIsolated {
                guard activeWindow === panel else { return }
                TadaSound.play()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + script.totalDuration + 1.8) {
            MainActor.assumeIsolated { dismiss() }
        }
    }
}

// MARK: - Simulation (fragmented → contiguous, pulling from the tail)

private struct OptimizerRun {
    let cols: Int
    let rows: Int
    let frontEnd: Int            // [0, frontEnd) is the region being consolidated
    let frontMask: [Bool]        // which front cells start occupied (rest are gaps)
    let gapPositions: [Int]      // sorted front gap indices
    let tailClusters: [Int]      // sorted tail fragment indices (consumed back-to-front)
    let chunks: [Chunk]
    let totalDuration: TimeInterval

    struct Chunk {
        let start: Int
        let length: Int
        let startTime: TimeInterval
        let duration: TimeInterval
    }

    init(width: CGFloat, height: CGFloat) {
        let cols = max(48, min(82, Int(width / 13)))
        let nominalW = width / CGFloat(cols)
        // Blocks slightly taller than wide — closer to the real grid.
        let rows = max(20, Int(height / (nominalW * 1.2)))
        let n = cols * rows
        self.cols = cols
        self.rows = rows

        // End partway through a row so the final consolidated row is partial
        // (~5/8 across), not a clean rectangle.
        let usedRows = max(1, Int(Double(rows) * 0.6))
        let frontEnd = min(n, usedRows * cols + Int(Double(cols) * 0.625))
        self.frontEnd = frontEnd

        var mask = [Bool](repeating: true, count: frontEnd)
        var gaps: [Int] = []
        for i in 0..<frontEnd {
            if Double.random(in: 0..<1) < 0.32 {   // ~32% gaps: a messy disk
                mask[i] = false
                gaps.append(i)
            }
        }
        self.frontMask = mask
        self.gapPositions = gaps

        // One tail fragment per front gap, scattered through the tail and
        // consumed from the bottom (highest index) first.
        let tailRange = Array(frontEnd..<n).shuffled()
        self.tailClusters = Array(tailRange.prefix(min(gaps.count, tailRange.count))).sorted()

        var chunks: [Chunk] = []
        var pos = 0
        var t: TimeInterval = 0
        while pos < frontEnd {
            let big = Int.random(in: 0..<11) == 0
            let want = big ? Int.random(in: 16...20) : Int.random(in: 1...4)
            let length = min(want, frontEnd - pos)
            let duration = big ? Double.random(in: 0.4...0.65)
                               : 0.06 + Double(length) * 0.03
            chunks.append(Chunk(start: pos, length: length, startTime: t, duration: duration))
            let gap = (Int.random(in: 0..<8) == 0) ? Double.random(in: 0.22...0.45)
                                                   : Double.random(in: 0.03...0.09)
            t += duration + gap
            pos += length
        }
        self.chunks = chunks
        self.totalDuration = t
    }

    func progress(at elapsed: TimeInterval) -> (head: Int, active: Chunk?) {
        var head = 0
        for chunk in chunks {
            let end = chunk.startTime + chunk.duration
            if end <= elapsed {
                head = chunk.start + chunk.length
            } else if chunk.startTime <= elapsed {
                return (chunk.start, chunk)
            } else {
                return (head, nil)
            }
        }
        return (frontEnd, nil)
    }

    /// The chunk currently being written, and whether it's a big band. Drives
    /// the disk-chatter so the sound matches the on-screen pace.
    func activeChunkIndex(at elapsed: TimeInterval) -> (index: Int, big: Bool)? {
        for (idx, chunk) in chunks.enumerated()
        where chunk.startTime <= elapsed && elapsed < chunk.startTime + chunk.duration {
            return (idx, chunk.length >= 16)
        }
        return nil
    }
}

/// Fires the chatter once per chunk, gated by pause. Held by the view as a
/// stable reference so it can dedupe across frame ticks.
@MainActor
private final class ChunkSoundDriver {
    private var lastIndex = -1
    func update(_ run: OptimizerRun, elapsed: TimeInterval, paused: Bool) {
        guard !paused, let (idx, big) = run.activeChunkIndex(at: elapsed), idx != lastIndex else { return }
        lastIndex = idx
        if big { DiskChatterSound.playRun() } else { DiskChatterSound.playTick() }
    }
}

// MARK: - Win98 palette + chrome

private enum Win98 {
    static let desktop  = Color(red: 0.0,  green: 0.50, blue: 0.50)
    static let face     = Color(red: 0.75, green: 0.75, blue: 0.75)
    static let hi       = Color.white
    static let liteGray = Color(red: 0.87, green: 0.87, blue: 0.87)
    static let shadow   = Color(red: 0.28, green: 0.28, blue: 0.28)
    static let dark     = Color.black
    static let titleA   = Color(red: 0.0,  green: 0.0,  blue: 0.50)
    static let titleB   = Color(red: 0.06, green: 0.52, blue: 0.82)

    static let grid       = Color.black
    static let used       = Color(red: 0.16, green: 0.80, blue: 0.86) // teal cluster
    static let checker    = Color(red: 0.10, green: 0.28, blue: 0.74) // medium-blue dither
    static let head       = Color(red: 0.88, green: 0.10, blue: 0.10) // red read/write band
    static let progress   = Color(red: 0.0,  green: 0.0,  blue: 0.55)
}

private struct Bevel: View {
    let raised: Bool
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                edge(w, h, 0.5, true,  raised ? Win98.hi : Win98.dark)
                edge(w, h, 0.5, false, raised ? Win98.dark : Win98.hi)
                edge(w, h, 1.5, true,  raised ? Win98.liteGray : Win98.shadow)
                edge(w, h, 1.5, false, raised ? Win98.shadow : Win98.liteGray)
            }
        }
        .allowsHitTesting(false)
    }

    private func edge(_ w: CGFloat, _ h: CGFloat, _ inset: CGFloat, _ topLeft: Bool, _ color: Color) -> some View {
        Path { p in
            if topLeft {
                p.move(to: CGPoint(x: inset, y: h - inset))
                p.addLine(to: CGPoint(x: inset, y: inset))
                p.addLine(to: CGPoint(x: w - inset, y: inset))
            } else {
                p.move(to: CGPoint(x: inset, y: h - inset))
                p.addLine(to: CGPoint(x: w - inset, y: h - inset))
                p.addLine(to: CGPoint(x: w - inset, y: inset))
            }
        }
        .stroke(color, lineWidth: 1)
    }
}

private struct Win98ButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundColor(.black)
            .frame(width: 116, height: 30)
            .background(Win98.face)
            .overlay(Bevel(raised: !configuration.isPressed))
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
    }
}

private enum CaptionKind { case minimize, maximize, close }

/// Win98 caption-button glyphs drawn by hand (SF Symbols don't match: the
/// minimize is a low underscore, the maximize a box with a thick top bar).
private struct CaptionGlyph: View {
    let kind: CaptionKind
    var body: some View {
        Canvas { ctx, size in
            let ink = GraphicsContext.Shading.color(.black)
            switch kind {
            case .minimize:
                let w: CGFloat = 9
                ctx.fill(Path(CGRect(x: (size.width - w) / 2, y: size.height - 3, width: w, height: 2)), with: ink)
            case .maximize:
                let bw: CGFloat = 13, bh: CGFloat = 11
                let x = (size.width - bw) / 2, y = (size.height - bh) / 2
                ctx.stroke(Path(CGRect(x: x, y: y, width: bw, height: bh)), with: ink, lineWidth: 1)
                ctx.fill(Path(CGRect(x: x, y: y, width: bw, height: 2.5)), with: ink)   // title bar
            case .close:
                let m: CGFloat = 3
                var p = Path()
                p.move(to: CGPoint(x: m, y: m)); p.addLine(to: CGPoint(x: size.width - m, y: size.height - m))
                p.move(to: CGPoint(x: size.width - m, y: m)); p.addLine(to: CGPoint(x: m, y: size.height - m))
                ctx.stroke(p, with: ink, lineWidth: 1.6)
            }
        }
        .frame(width: 15, height: 13)
    }
}

private struct DefragWindowView: View {
    let script: OptimizerRun
    let startDate: Date
    let screenSize: CGSize
    let windowSize: CGSize
    let onStop: () -> Void

    @State private var pausedAccum: TimeInterval = 0
    @State private var pauseStartedAt: Date? = nil
    @State private var detailsHidden = false
    @State private var showLegend = false
    @State private var sound = ChunkSoundDriver()

    private var isPaused: Bool { pauseStartedAt != nil }

    private func elapsed(_ now: Date) -> TimeInterval {
        let raw = now.timeIntervalSince(startDate) - pausedAccum
        if let p = pauseStartedAt { return raw - now.timeIntervalSince(p) }
        return raw
    }

    var body: some View {
        let winW = detailsHidden ? min(580, windowSize.width) : windowSize.width
        let winH = detailsHidden ? 134 : windowSize.height
        ZStack {
            Win98.desktop.ignoresSafeArea()
            window
                .frame(width: winW, height: winH)
                .overlay(Bevel(raised: true))
            if showLegend { legend }
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }

    private var window: some View {
        VStack(spacing: 0) {
            titleBar
            VStack(spacing: 12) {
                if !detailsHidden { gridWell }
                bottomControls
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Win98.face)
        .background(soundTicker)
    }

    /// Zero-cost, always-present timeline so the chatter stays synced to the
    /// run even when the grid is collapsed (Hide Details).
    private var soundTicker: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let _ = sound.update(script, elapsed: elapsed(context.date), paused: isPaused)
            Color.clear
        }
    }

    private var titleBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "internaldrive").font(.system(size: 14)).foregroundColor(.white)
            Text(verbatim: "Defragmenting Drive C")
                .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
            Spacer()
            HStack(spacing: 2) {
                captionButton(.minimize) {}
                captionButton(.maximize) {}
                captionButton(.close) { onStop() }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 28)
        .background(LinearGradient(colors: [Win98.titleA, Win98.titleB],
                                   startPoint: .leading, endPoint: .trailing))
        .padding(3)
    }

    private func captionButton(_ kind: CaptionKind, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Rectangle().fill(Win98.face)
                CaptionGlyph(kind: kind)
            }
            .frame(width: 23, height: 20)
            .overlay(Bevel(raised: true))
        }
        .buttonStyle(.plain)
    }

    private var gridWell: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            Canvas { ctx, size in
                draw(ctx: &ctx, size: size, elapsed: elapsed(context.date))
            }
        }
        .background(Color.white)
        .overlay(Bevel(raised: false))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomControls: some View {
        HStack(alignment: .bottom, spacing: 18) {
            TimelineView(.periodic(from: startDate, by: 0.2)) { context in
                let pct = percent(at: context.date)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "Defragmenting file system...")
                        .font(.system(size: 14)).foregroundColor(.black)
                    progressBar(pct: pct).frame(height: 24)
                    Text(verbatim: "\(pct)% Complete")
                        .font(.system(size: 14)).foregroundColor(.black)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button("Stop") { onStop() }.buttonStyle(Win98ButtonStyle())
                    Button(isPaused ? "Resume" : "Pause") { togglePause() }.buttonStyle(Win98ButtonStyle())
                }
                HStack(spacing: 8) {
                    Button("Legend") { showLegend.toggle() }.buttonStyle(Win98ButtonStyle())
                    Button(detailsHidden ? "Show Details" : "Hide Details") { detailsHidden.toggle() }
                        .buttonStyle(Win98ButtonStyle())
                }
            }
        }
    }

    private func progressBar(pct: Int) -> some View {
        GeometryReader { g in
            let gap: CGFloat = 2, target: CGFloat = 9
            let available = g.size.width - 8
            let count = max(1, Int((available + gap) / (target + gap)))
            // Size ticks to span the full trough so 100% fills it exactly.
            let tickW = (available - CGFloat(count - 1) * gap) / CGFloat(count)
            let filled = Int((Double(pct) / 100.0 * Double(count)).rounded())
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { i in
                    Rectangle().fill(i < filled ? Win98.progress : Color.clear).frame(width: tickW)
                }
            }
            .padding(4)
        }
        .background(Color.white)
        .overlay(Bevel(raised: false))
    }

    private var legend: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text(verbatim: "Legend").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(LinearGradient(colors: [Win98.titleA, Win98.titleB], startPoint: .leading, endPoint: .trailing))
            .padding(3)

            VStack(alignment: .leading, spacing: 8) {
                legendRow(Win98.used, "Fragmented data")
                legendRow(Win98.checker, "Contiguous (optimized) data")
                legendRow(Win98.head, "Data being read/written")
                legendRow(.white, "Free space")
                Button("Close") { showLegend = false }.buttonStyle(Win98ButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(12)
        }
        .frame(width: 280)
        .background(Win98.face)
        .overlay(Bevel(raised: true))
    }

    private func legendRow(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 9) {
            Rectangle().fill(color).frame(width: 18, height: 16).overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
            Text(verbatim: label).font(.system(size: 14)).foregroundColor(.black)
        }
    }

    private func togglePause() {
        let now = Date()
        if let p = pauseStartedAt {
            pausedAccum += now.timeIntervalSince(p)
            pauseStartedAt = nil
        } else {
            pauseStartedAt = now
        }
    }

    private func percent(at date: Date) -> Int {
        guard script.frontEnd > 0 else { return 100 }
        let (head, _) = script.progress(at: elapsed(date))
        return min(100, max(0, Int(Double(head) / Double(script.frontEnd) * 100)))
    }

    // MARK: grid rendering

    private func draw(ctx: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let cols = script.cols, rows = script.rows, n = cols * rows
        let pad: CGFloat = 3   // margin between the block grid and the well edge
        let cellW = (size.width - pad * 2) / CGFloat(cols)
        let cellH = (size.height - pad * 2) / CGFloat(rows)
        let (head, active) = script.progress(at: elapsed)
        let activeStart = active?.start ?? head
        let activeEnd = activeStart + (active?.length ?? 0)

        // Tail fragments consumed back-to-front as front gaps fill.
        let gapsFilled = script.gapPositions.firstIndex(where: { $0 >= head }) ?? script.gapPositions.count
        let tailRemaining = max(0, script.tailClusters.count - gapsFilled)

        let margin: CGFloat = 0.75   // ~1.5px gap between adjacent blocks
        let border: CGFloat = 1.0

        func cellRect(_ i: Int) -> CGRect {
            let col = i % cols, row = i / cols
            return CGRect(x: pad + CGFloat(col) * cellW, y: pad + CGFloat(row) * cellH, width: cellW, height: cellH)
        }
        func block(_ i: Int) -> CGRect { cellRect(i).insetBy(dx: margin, dy: margin) }
        func inner(_ i: Int) -> CGRect { block(i).insetBy(dx: border, dy: border) }

        var blackPath = Path(), usedPath = Path(), optPath = Path(), headPath = Path()
        var dots = Path()

        func emit(_ i: Int, _ kind: Int) {   // 0 used, 1 optimized, 2 head
            blackPath.addRect(block(i))
            let r = inner(i)
            switch kind {
            case 1: optPath.addRect(r); addChecker(&dots, in: r)
            case 2: headPath.addRect(r)
            default: usedPath.addRect(r)
            }
        }

        for i in 0..<min(script.frontEnd, n) {
            if i >= activeStart && i < activeEnd {
                emit(i, 2)
            } else if i < head {
                emit(i, 1)
            } else if script.frontMask[i] {
                emit(i, 0)
            }
            // gaps ahead of the head: leave white, no border.
        }
        for j in 0..<min(tailRemaining, script.tailClusters.count) {
            emit(script.tailClusters[j], 0)
        }

        ctx.fill(blackPath, with: .color(Win98.grid))
        ctx.fill(usedPath, with: .color(Win98.used))
        ctx.fill(optPath, with: .color(Win98.used))   // teal base under the dither
        ctx.fill(dots, with: .color(Win98.checker))
        ctx.fill(headPath, with: .color(Win98.head))
    }

    /// Medium-blue checkerboard dither over the teal block — ~2px squares.
    private func addChecker(_ path: inout Path, in r: CGRect) {
        let target: CGFloat = 1.0
        let subX = max(2, min(8, Int((r.width / target).rounded())))
        let subY = max(2, min(12, Int((r.height / target).rounded())))
        let sw = r.width / CGFloat(subX), sh = r.height / CGFloat(subY)
        for sy in 0..<subY {
            for sx in 0..<subX where (sx + sy) % 2 == 0 {
                path.addRect(CGRect(x: r.minX + CGFloat(sx) * sw,
                                    y: r.minY + CGFloat(sy) * sh,
                                    width: sw, height: sh))
            }
        }
    }
}
