import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Three-window Celery Man arrangement. Triggered by `:celery:`.
///
/// Layout (Tim & Eric reference still):
///   - LEFT:  "Celery Man" — landscape clip (v04), starts as the original
///   - RIGHT: "CINCO ID" — portrait clip (v03), starts as the original
///   - BELOW (between/under): "Paul's COMPUTER" — fake file-panel mock,
///                            inert until clicked once.
///
/// First click anywhere inside Paul's COMPUTER swaps the two video windows'
/// sources to the alternates (v09 for Celery Man, v10 for CINCO ID). Further
/// clicks do nothing. Audio loop (`s14`, the celery.wav) plays the whole time
/// any window in the trio is open.
@MainActor
enum CeleryMan {
    private static var windows: Set<NSWindow> = []
    private static var observers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private static var audioPlayer: AVAudioPlayer?
    /// One-shot player for the "4d3d3d3-engage" chant fired when Paul's
    /// COMPUTER is clicked. Held statically so it doesn't get released
    /// mid-playback.
    private static var engagePlayer: NSSound?
    /// Refs to the two video windows' SwiftUI host views so Paul's click can
    /// swap them. Held weakly via the underlying NSWindow.
    private static weak var celeryHost: SwappableVideoHostingView?
    private static weak var cincoHost: SwappableVideoHostingView?
    /// One-shot guard for Paul's swap.
    private static var didSwap: Bool = false

    static func start() {
        // If already open, bring forward.
        if !windows.isEmpty {
            for w in windows { w.makeKeyAndOrderFront(nil) }
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        didSwap = false

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame

        // Sizes — side-by-side arrangement, baseline-aligned.
        //   - Celery Man (landscape): 30% smaller than the prior 320pt height.
        //   - CINCO ID (portrait):    20% taller than the prior 320pt height.
        //   - Paul's COMPUTER:        small panel anchored under the videos.
        let celeryHeight: CGFloat = 320 * 0.7
        let celerySize = NSSize(width: celeryHeight * 300.0 / 206.0, height: celeryHeight)
        let cincoHeight: CGFloat = 320 * 1.2
        let cincoSize  = NSSize(width: cincoHeight * 180.0 / 290.0, height: cincoHeight)
        let paulSize   = NSSize(width: 320, height: 130)
        let columnGap: CGFloat = 24
        let interGap:  CGFloat = 16

        let videosWidth = celerySize.width + columnGap + cincoSize.width
        let videosX = visible.midX - videosWidth / 2

        // Center the trio vertically using the tallest column (CINCO + Paul's).
        let trioHeight = cincoSize.height + interGap + paulSize.height
        let trioBottom = visible.midY - trioHeight / 2
        let videoBaseline = trioBottom + paulSize.height + interGap

        let celeryX = videosX
        let cincoX  = videosX + celerySize.width + columnGap
        // Both video windows share `videoBaseline` as their bottom edge —
        // shorter Celery floats above, taller CINCO reaches higher up.
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

    /// Called by Paul's COMPUTER's click handler. One-shot: fire the
    /// "4d3d3d3 engage" chant immediately and swap the two video sources
    /// 2s into the audio so the visual change lands on cue with the
    /// reference (Tim & Eric's Paul says the line *before* the new clips
    /// appear).
    private static func handlePaulClicked() {
        guard !didSwap else { return }
        didSwap = true
        // Fire the engage chant first. AudioBlob is the standard scrambled
        // loader; s16.bin is 4d3d3d3d.wav.
        if let sound = AudioBlob.load("s16") {
            engagePlayer = sound
            sound.play()
        }
        // Hold the videos on their original clips until the chant has been
        // playing for ~2s, then swap (celery6/v09 → CINCO, celery9/v10 →
        // Celery Man — flipped from the previous round on purpose).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            celeryHost?.swap(to: "v10")
            cincoHost?.swap(to: "v09")
        }
    }

    /// Common window setup + observer wiring. The two video windows now
    /// keep a normal macOS titlebar (so the videos aren't headerless);
    /// Paul's COMPUTER keeps the transparent style so its dark mock
    /// terminal extends under the chrome.
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

    /// Esc-in-focused-window handler — closes the whole trio at once.
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

/// AVPlayerLayer-hosting NSView whose video source can be swapped at runtime.
/// Used by Celery Man / CINCO ID so Paul's COMPUTER's click can switch them
/// over to the alternate clips in place.
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
        // Stop and tear down the previous player + layer cleanly before
        // installing the replacement. Avoids the looper continuing to drive
        // a layer we just removed.
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

/// "Paul's COMPUTER" — an NSView (not SwiftUI) so the entire surface is
/// click-capturable without fighting SwiftUI's hit testing. Single fire
/// callback on the first mouseDown.
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

/// Observable shared between the click NSView and the SwiftUI contents so
/// the typewriter "4d3d3d3 Engaged" reveal can kick off on mouseDown.
@MainActor
private final class PaulsClickedModel: ObservableObject {
    @Published var clicked: Bool = false
}

private struct PaulsComputerContents: View {
    @ObservedObject var model: PaulsClickedModel
    @State private var typedCount: Int = 0
    @State private var typeTimer: Timer?

    private let engagedText = "4d3d3d3 Engaged"

    var body: some View {
        ZStack {
            Color.black
            VStack(alignment: .leading, spacing: 8) {
                Text("C:\\")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 1)

                // Cmdline / file row. Pre-click reads "Kick up 4d3d3d3";
                // post-click types out "4d3d3d3 Engaged" one char at a time.
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
            typeTimer?.invalidate()
            typeTimer = nil
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
        typeTimer?.invalidate()
        let total = engagedText.count
        typeTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { t in
            DispatchQueue.main.async {
                if typedCount >= total {
                    t.invalidate()
                    return
                }
                typedCount += 1
            }
        }
    }
}
