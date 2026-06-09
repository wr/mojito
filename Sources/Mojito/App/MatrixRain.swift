import AppKit
import CoreGraphics
import CoreText

/// Cascading green katakana/digits. Layer-backed NSView draws all columns
/// in one Core Text pass per tick (30 Hz).
@MainActor
enum MatrixRain {
    private static var activeWindow: NSWindow?

    static func start(duration: TimeInterval = 7.0) {
        guard let frame = ParticlePanel.primaryScreenFrame() else { return }

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
                panel.contentView = nil
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

@MainActor
private final class MatrixHostView: NSView {
    private let duration: TimeInterval
    private let ticker = AnimationTicker()
    private var columns: [MatrixColumn] = []
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

    override var isFlipped: Bool { true }  // top-left origin

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
        // 30 Hz halves CPU vs 60 Hz; cascade still reads smoothly.
        ticker.start(interval: 1.0 / 30.0) { [weak self] elapsed in
            self?.advance(elapsed: elapsed)
        }
    }

    func stop() {
        ticker.stop()
        columns.removeAll()
    }

    private func advance(elapsed: TimeInterval) {
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
        let elapsed = ticker.elapsed
        let globalFade = elapsed > duration - 0.6
            ? max(0.0, (duration - elapsed) / 0.6)
            : 1.0

        let viewBounds = bounds
        // AppKit's monospaced font — CT's default renders no-glyph boxes for katakana.
        let font = NSFont.monospacedSystemFont(ofSize: glyphSize, weight: .regular)

        let bodyColor = NSColor(red: 0.0, green: 0.85, blue: 0.25, alpha: 1)
        let headColor = NSColor(red: 0.92, green: 1.0, blue: 0.92, alpha: 1)

        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        // Mutate one attrs dict instead of allocating per glyph.
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
