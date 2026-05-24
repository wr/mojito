import AppKit
import CoreGraphics
import CoreText

/// Cascading green katakana/digits. Triggered by `:matrix:`.
///
/// Implementation: a single layer-backed NSView that draws all columns in
/// one `draw(_:)` pass per tick. We tried per-column CATextLayers in a
/// previous iteration but the multi-line CATextLayer + mask + frame-driven
/// positioning combo rendered nothing visible (glyphs clipped to a too-
/// narrow column box, mask coordinate-space mismatches). One direct
/// Core Text pass per frame is well within budget at 30 Hz for a few
/// hundred columns and gives us pixel-perfect control over fade + head
/// highlight.
@MainActor
enum MatrixRain {
    private static var activeWindow: NSWindow?

    static func start(duration: TimeInterval = 7.0) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        activeWindow?.orderOut(nil)
        activeWindow = nil

        let panel = ParticlePanel.makeFullScreen(frame: frame)
        let view = MatrixHostView(frame: NSRect(origin: .zero, size: frame.size), duration: duration)
        panel.contentView = view
        panel.orderFrontRegardless()
        activeWindow = panel

        var cancelToken: (() -> Void)?
        let dismiss = {
            MainActor.assumeIsolated {
                view.stop()
                panel.orderOut(nil)
                cancelToken?(); cancelToken = nil
                if activeWindow === panel { activeWindow = nil }
            }
        }
        cancelToken = EffectDismisser.register(dismiss)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) {
            MainActor.assumeIsolated { dismiss() }
        }
    }
}

/// Custom-drawn NSView. Each tick the timer advances column phases and
/// triggers a redraw; `draw(_:)` walks the columns and paints glyph stacks
/// directly into the current CGContext. Tear-down is explicit via stop()
/// to invalidate the timer + drop column refs.
@MainActor
private final class MatrixHostView: NSView {
    private let duration: TimeInterval
    private var tickTimer: Timer?
    private var columns: [MatrixColumn] = []
    private let startDate = Date()
    private let glyphPool: [String]
    private let glyphSize: CGFloat = 24
    private let columnSpacing: CGFloat = 20

    init(frame: NSRect, duration: TimeInterval) {
        self.duration = duration
        self.glyphPool = Array(
            "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜｦﾝ" +
            "0123456789ABCDEFｦｧｨｩｪｫｬｭｮｯ$+-=*<>?:;|!@#%&^"
        ).map { String($0) }
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.96).cgColor

        buildColumns(in: frame)
        start()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// Cocoa default is flipped == false (origin bottom-left). We're going
    /// to draw glyphs top-down so flipped == true keeps the math obvious.
    override var isFlipped: Bool { true }

    private func buildColumns(in frame: NSRect) {
        let columnCount = Int(frame.width / columnSpacing) + 1
        columns.reserveCapacity(columnCount)
        for i in 0..<columnCount {
            let tail = Int.random(in: 18...40)
            var glyphs = [String]()
            glyphs.reserveCapacity(tail)
            for _ in 0..<tail {
                glyphs.append(glyphPool.randomElement() ?? "0")
            }
            columns.append(MatrixColumn(
                x: CGFloat(i) * columnSpacing,
                speed: .random(in: 220...460),
                tailLength: tail,
                startOffset: .random(in: 0...frame.height * 2),
                cycleEvery: .random(in: 0.08...0.18),
                glyphs: glyphs,
                lastCycleStep: -1
            ))
        }
    }

    private func start() {
        // 30 Hz is enough for the cascade feel; lower than 60 Hz halves CPU.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.advance()
                }
            }
        }
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        columns.removeAll()
    }

    deinit {
        if let t = tickTimer { t.invalidate() }
    }

    private func advance() {
        let elapsed = Date().timeIntervalSince(startDate)
        // Re-roll the glyphs for any column that's past its cycle window.
        for i in columns.indices {
            let step = Int(elapsed / columns[i].cycleEvery)
            if step != columns[i].lastCycleStep {
                columns[i].lastCycleStep = step
                for j in columns[i].glyphs.indices {
                    columns[i].glyphs[j] = glyphPool.randomElement() ?? "0"
                }
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let elapsed = Date().timeIntervalSince(startDate)
        let globalFade = elapsed > duration - 0.6
            ? max(0.0, (duration - elapsed) / 0.6)
            : 1.0

        let viewBounds = bounds
        // Use the AppKit monospaced font so katakana actually renders
        // (vs. CT's default that often falls back to a no-glyph box).
        let font = NSFont.monospacedSystemFont(ofSize: glyphSize, weight: .regular)

        let bodyColor = NSColor(red: 0.0, green: 0.85, blue: 0.25, alpha: 1)
        let headColor = NSColor(red: 0.92, green: 1.0, blue: 0.92, alpha: 1)

        // Flip context y-axis once; subsequent text positions are in the
        // flipped frame so we just bump textPosition per glyph.
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        // Cache an NSString attrs dict; mutate the foreground color per glyph
        // rather than alloc-ing a new attributedString every time. CTLine
        // allocation per glyph is unavoidable since the string changes, but
        // the dict reuse keeps the per-glyph alloc count to one.
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.green.cgColor,
        ]

        for col in columns {
            let totalDistance = viewBounds.height + CGFloat(col.tailLength) * glyphSize
            let phase = (col.startOffset + col.speed * CGFloat(elapsed))
                .truncatingRemainder(dividingBy: totalDistance)
            let headY = phase

            for j in 0..<col.tailLength {
                let y = headY - CGFloat(j) * glyphSize
                if y + glyphSize < 0 || y > viewBounds.height { continue }
                let t = CGFloat(j) / CGFloat(col.tailLength)
                let alpha = max(0.02, (1.0 - t)) * globalFade
                let base = (j == 0) ? headColor : bodyColor
                attrs[.foregroundColor] = base.withAlphaComponent(alpha).cgColor

                let attr = NSAttributedString(string: col.glyphs[j], attributes: attrs)
                let line = CTLineCreateWithAttributedString(attr)
                ctx.textPosition = CGPoint(x: col.x, y: y + glyphSize * 0.85)
                CTLineDraw(line, ctx)
            }
        }
        ctx.restoreGState()
    }
}

private struct MatrixColumn {
    let x: CGFloat
    let speed: CGFloat
    let tailLength: Int
    let startOffset: CGFloat
    let cycleEvery: Double
    var glyphs: [String]
    var lastCycleStep: Int
}
