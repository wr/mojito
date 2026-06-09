import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Tim & Eric Celery Man trio: Celery Man (left, v04), CINCO ID (right,
/// v03), Paul's COMPUTER (below, inert until clicked). First click on
/// Paul swaps the two video sources to v10 / v09. Audio loop (`s14`)
/// plays whenever any window is open.
@MainActor
enum CeleryMan {
    private static var windows: Set<NSWindow> = []
    private static var observers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private static var audioPlayer: AVAudioPlayer?
    /// Static so it isn't released mid-playback.
    private static var engagePlayer: NSSound?
    /// Weak via the underlying NSWindow.
    private static weak var celeryHost: SwappableVideoHostingView?
    private static weak var cincoHost: SwappableVideoHostingView?
    private static var didSwap: Bool = false

    static func start() {
        if !windows.isEmpty {
            for w in windows { w.makeKeyAndOrderFront(nil) }
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        didSwap = false

        guard let screen = ParticlePanel.primaryScreen() else { return }
        let visible = screen.visibleFrame

        // 320pt baseline; landscape × 0.91, portrait × 1.56, Paul under both.
        let celeryHeight: CGFloat = 320 * 0.91
        let celerySize = NSSize(width: celeryHeight * 300.0 / 206.0, height: celeryHeight)
        let cincoHeight: CGFloat = 320 * 1.56
        let cincoSize  = NSSize(width: cincoHeight * 180.0 / 290.0, height: cincoHeight)
        let paulSize   = NSSize(width: 320, height: 130)
        let columnGap: CGFloat = 24
        let interGap:  CGFloat = 16

        let videosWidth = celerySize.width + columnGap + cincoSize.width
        let videosX = visible.midX - videosWidth / 2

        // Center on the tallest column (CINCO + Paul's).
        let trioHeight = cincoSize.height + interGap + paulSize.height
        let trioBottom = visible.midY - trioHeight / 2
        let videoBaseline = trioBottom + paulSize.height + interGap

        let celeryX = videosX
        let cincoX  = videosX + celerySize.width + columnGap
        // Both share `videoBaseline` as their bottom; CINCO reaches higher.
        let celeryY = videoBaseline
        let cincoY  = videoBaseline

        let paulX = visible.midX - paulSize.width / 2
        let paulY = trioBottom

        let celeryView = SwappableVideoHostingView(initialClip: "v04")
        celeryView.frame = CGRect(origin: .zero, size: celerySize)
        celeryHost = celeryView
        installWindow(
            title: "Celery Man",
            origin: NSPoint(x: celeryX, y: celeryY),
            size: celerySize,
            content: celeryView,
            transparentTitlebar: false
        )

        let cincoView = SwappableVideoHostingView(initialClip: "v03")
        cincoView.frame = CGRect(origin: .zero, size: cincoSize)
        cincoHost = cincoView
        installWindow(
            title: "CINCO ID",
            origin: NSPoint(x: cincoX, y: cincoY),
            size: cincoSize,
            content: cincoView,
            transparentTitlebar: false
        )

        let paulView = PaulsComputerClickView(frame: CGRect(origin: .zero, size: paulSize)) {
            handlePaulClicked()
        }
        installWindow(
            title: "Paul's COMPUTER",
            origin: NSPoint(x: paulX, y: paulY),
            size: paulSize,
            content: paulView
        )

        ensureAudioPlaying()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Fire the chant, then swap 2s in — Paul says the line *before*
    /// the new clips appear in the reference.
    private static func handlePaulClicked() {
        guard !didSwap else { return }
        didSwap = true
        // s16.bin is 4d3d3d3d.wav.
        if let sound = AudioBlob.load("s16") {
            engagePlayer = sound
            sound.play()
        }
        // v09/v10 are swapped from the previous round on purpose.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            celeryHost?.swap(to: "v10")
            cincoHost?.swap(to: "v09")
        }
    }

    /// Videos keep a normal titlebar; Paul's COMPUTER stays transparent
    /// so its mock terminal extends under the chrome.
    private static func installWindow(title: String, origin: NSPoint, size: NSSize, content: NSView, transparentTitlebar: Bool = true) {
        let styleMask: NSWindow.StyleMask = transparentTitlebar
            ? [.titled, .closable, .fullSizeContentView]
            : [.titled, .closable]
        let w = CeleryWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        w.title = title
        if transparentTitlebar {
            w.titlebarAppearsTransparent = true
        }
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        w.level = .floating
        w.standardWindowButton(.zoomButton)?.isHidden = true
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.onCancel = { closeAll() }

        w.contentView = content

        windows.insert(w)
        DockIconManager.windowDidOpen()
        // Also drops the content view at close, so video playback /
        // typewriter teardown happens then, not at some later dealloc.
        ParticlePanel.tearDownOnClose(w)

        observers[ObjectIdentifier(w)] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: w,
            queue: .main
        ) { note in
            MainActor.assumeIsolated {
                guard let closed = note.object as? NSWindow else { return }
                let cid = ObjectIdentifier(closed)
                if let obs = observers.removeValue(forKey: cid) {
                    NotificationCenter.default.removeObserver(obs)
                }
                if windows.remove(closed) != nil {
                    DockIconManager.windowDidClose()
                }
                if windows.isEmpty {
                    stopAudio()
                }
            }
        }

        w.makeKeyAndOrderFront(nil)
    }

    /// Esc handler — closes the whole trio.
    private static func closeAll() {
        for w in windows { w.close() }
    }

    private static func ensureAudioPlaying() {
        if let p = audioPlayer, p.isPlaying { return }
        guard let url = Bundle.main.url(forResource: "s14", withExtension: "bin"),
              let raw = try? Data(contentsOf: url) else { return }
        var decoded = Data(count: raw.count)
        decoded.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) in
            raw.withUnsafeBytes { (inp: UnsafeRawBufferPointer) in
                let outBytes = out.bindMemory(to: UInt8.self)
                let inBytes = inp.bindMemory(to: UInt8.self)
                for i in 0..<raw.count {
                    outBytes[i] = inBytes[i] ^ 0x5A
                }
            }
        }
        guard let player = try? AVAudioPlayer(data: decoded) else { return }
        player.numberOfLoops = -1
        player.prepareToPlay()
        player.play()
        audioPlayer = player
    }

    private static func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}

/// NSWindow subclass that routes Esc (`cancelOperation`) to a callback.
private final class CeleryWindow: NSWindow {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Video source can be swapped at runtime so Paul's click switches the
/// Celery Man / CINCO ID windows over in place.
@MainActor
private final class SwappableVideoHostingView: NSView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    init(initialClip: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        install(clip: initialClip)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    func swap(to clipName: String) {
        // Tear down cleanly so the looper doesn't keep driving a layer
        // we just removed.
        player?.pause()
        looper = nil
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        install(clip: clipName)
    }

    private func install(clip name: String) {
        guard let url = VideoBlob.url(name) else { return }
        let item = AVPlayerItem(url: url)
        let q = AVQueuePlayer()
        q.isMuted = true
        let l = AVPlayerLooper(player: q, templateItem: item)
        let lyr = AVPlayerLayer(player: q)
        lyr.videoGravity = .resizeAspect
        lyr.frame = bounds
        layer?.addSublayer(lyr)
        player = q
        looper = l
        playerLayer = lyr
        q.play()
    }
}

/// NSView (not SwiftUI) so the whole surface is click-capturable
/// without fighting SwiftUI's hit testing. One-shot mouseDown callback.
@MainActor
private final class PaulsComputerClickView: NSView {
    private let onClick: () -> Void
    private var fired = false
    private let model = PaulsClickedModel()

    init(frame: NSRect, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        let host = NSHostingView(rootView: PaulsComputerContents(model: model))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func mouseDown(with event: NSEvent) {
        if fired { return }
        fired = true
        model.clicked = true
        onClick()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !fired {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

/// Shared so the SwiftUI contents can kick off the typewriter on mouseDown.
@MainActor
private final class PaulsClickedModel: ObservableObject {
    @Published var clicked: Bool = false
}

private struct PaulsComputerContents: View {
    @ObservedObject var model: PaulsClickedModel
    @State private var typedCount: Int = 0
    @State private var typeTicker = AnimationTicker()

    private let engagedText = "4d3d3d3 Engaged"

    var body: some View {
        ZStack {
            Color.black
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "C:\\")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 1)

                // Pre-click: "Kick up 4d3d3d3". Post-click: typewriter
                // "4d3d3d3 Engaged".
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 14, height: 18)
                        .overlay(
                            VStack(spacing: 1.5) {
                                Rectangle().fill(Color.black.opacity(0.3)).frame(height: 1)
                                Rectangle().fill(Color.black.opacity(0.3)).frame(height: 1)
                                Rectangle().fill(Color.black.opacity(0.3)).frame(height: 1)
                            }
                            .padding(.horizontal, 2.5)
                        )

                    Text(displayText)
                        .font(.system(size: 20, weight: .regular, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                }
                Spacer()
            }
            .padding(14)
            .allowsHitTesting(false)  // forward clicks to the parent NSView
        }
        .onChange(of: model.clicked) { _, isClicked in
            if isClicked { startTyping() }
        }
        .onDisappear {
            typeTicker.stop()
        }
    }

    private var displayText: String {
        if !model.clicked {
            return "Kick up 4d3d3d3"
        }
        let chars = Array(engagedText)
        return String(chars.prefix(min(typedCount, chars.count)))
    }

    private func startTyping() {
        typedCount = 0
        let total = engagedText.count
        typeTicker.start(interval: 0.08) { _ in
            if typedCount >= total {
                typeTicker.stop()
                return
            }
            typedCount += 1
        }
    }
}
