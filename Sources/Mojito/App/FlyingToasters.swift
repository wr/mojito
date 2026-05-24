import AppKit

/// After Dark's Flying Toasters: 100×100 winged-toaster sprite (`v12.bin`,
/// XOR-scrambled GIF) drifts top-right → bottom-left, repeated ~14 times
/// with randomized start, speed, and launch delay. GIF wing-flap animation
/// is driven by `NSImageView.animates`, not redrawn.
@MainActor
enum FlyingToasters {
    private static var activeWindow: NSWindow?
    private static let sprite: NSImage? = ImageBlob.load("v12")

    static func start(duration: TimeInterval = 8.0) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        activeWindow?.orderOut(nil)
        activeWindow = nil

        let itemCount = 14
        var items: [Toaster] = []
        items.reserveCapacity(itemCount)
        for _ in 0..<itemCount {
            // Start above/right of bounds; travel down-left.
            let startX = CGFloat.random(in: frame.width * 0.3...frame.width * 1.4)
            let startY = CGFloat.random(in: -frame.height * 0.4...frame.height * 0.4)
            items.append(Toaster(
                startX: startX,
                startY: startY,
                speed: .random(in: 80...160),
                launchTime: .random(in: 0..<(duration * 0.6))
            ))
        }

        let panel = ParticlePanel.makeFullScreen(frame: frame)
        let field = ToasterField(
            sprite: sprite,
            items: items,
            bounds: frame.size,
            duration: duration
        )
        panel.contentView = field
        panel.orderFrontRegardless()
        activeWindow = panel
        field.start()

        var cancelToken: (() -> Void)?
        let dismiss = {
            MainActor.assumeIsolated {
                field.stop()
                panel.orderOut(nil)
                cancelToken?(); cancelToken = nil
                if activeWindow === panel { activeWindow = nil }
            }
        }
        cancelToken = EffectDismisser.register(dismiss)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.3) {
            MainActor.assumeIsolated { dismiss() }
        }
    }
}

private struct Toaster {
    let startX: CGFloat
    let startY: CGFloat
    let speed: CGFloat
    let launchTime: TimeInterval
}

private final class ToasterField: NSView {
    private let items: [Toaster]
    private let imageViews: [NSImageView]
    private let bounds_: CGSize
    private let duration: TimeInterval
    private var startDate: Date = Date()
    private var timer: Timer?
    /// 100×100 sprite; keeping native size — looks tiny on a 5K display
    /// but matches the After Dark feel.
    private let spriteSize: CGFloat = 100

    init(sprite: NSImage?, items: [Toaster], bounds: CGSize, duration: TimeInterval) {
        self.items = items
        self.bounds_ = bounds
        self.duration = duration
        self.imageViews = items.map { _ in
            let iv = NSImageView()
            iv.image = sprite
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.animates = true
            iv.isHidden = true
            return iv
        }
        super.init(frame: CGRect(origin: .zero, size: bounds))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        for iv in imageViews { addSubview(iv) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func start() {
        startDate = Date()
        // 60 Hz movement; GIF wing-flap is driven independently by NSImageView.
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let elapsed = Date().timeIntervalSince(startDate)
        // Last 0.5 s: fade the container so toasters trail out together.
        let endFade: CGFloat = elapsed > duration - 0.5
            ? max(0.0, CGFloat((duration - elapsed) / 0.5))
            : 1.0
        layer?.opacity = Float(endFade)

        // ~30° below horizontal, leftward — matches the old Canvas vector.
        let angle = Double.pi / 6
        let cosA = CGFloat(cos(angle))
        let sinA = CGFloat(sin(angle))

        for (i, item) in items.enumerated() {
            let iv = imageViews[i]
            let t = elapsed - item.launchTime
            guard t > 0 else { iv.isHidden = true; continue }

            let dx = -cosA * item.speed * CGFloat(t)
            let dy = sinA * item.speed * CGFloat(t)
            let x = item.startX + dx
            // Canvas coords are y-down; NSView coords are y-up. Flip.
            let yDown = item.startY + dy
            let y = bounds_.height - yDown - spriteSize

            // Cull once the sprite has cleared the left edge or fallen
            // off the bottom (matches the old Canvas culling).
            if x < -spriteSize - 20 || yDown > bounds_.height + 120 {
                iv.isHidden = true
                continue
            }
            iv.isHidden = false
            iv.frame = CGRect(x: x, y: y, width: spriteSize, height: spriteSize)
        }
    }
}
