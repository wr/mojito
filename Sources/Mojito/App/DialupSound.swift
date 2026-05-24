import AppKit
import SwiftUI

/// "Connecting To Mojito Online…" — what if Apple shipped a dial-up modem
/// dialog in macOS Tahoe? Triggered by `:dialup:`.
///
/// Real titled NSWindow with system stoplights, behind-window glass, native
/// SF Pro typography, the Mojito menubar mark, and SF Symbols animating
/// via SwiftUI's symbolEffect. The handshake sound plays while the window
/// is open; closing the window (stoplight, Esc) stops it. The window also
/// auto-dismisses a couple of seconds after "Connected!" lands.
@MainActor
enum DialupSound {
    fileprivate static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?
    private static var player: NSSound?
    private static var dismissWorkItem: DispatchWorkItem?

    /// Stage timing (seconds since open). Tuned so dialing dominates, then a
    /// long "connecting" stretch, then "Connected!" arrives at ~20s and
    /// holds for 3s before the window auto-dismisses.
    fileprivate static let stageBreakpoints = (
        dialingEnd:    6.0,
        connectingEnd: 27.0,
        autoDismiss:   30.0
    )

    static func play() {
        if let existing = window {
            existing.orderFrontRegardless()
            return
        }

        let size = NSSize(width: 672, height: 436)
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.title = "Mojito Online"
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.backgroundColor = .clear
        w.center()
        w.level = .floating
        w.standardWindowButton(.zoomButton)?.isHidden = true

        // Glass background — NSVisualEffectView pinned to the window's content frame.
        let glass = NSVisualEffectView()
        glass.material = .windowBackground
        glass.state = .active
        glass.blendingMode = .behindWindow
        glass.translatesAutoresizingMaskIntoConstraints = false

        let host = NSHostingView(rootView: DialupView(
            startDate: Date(),
            onDismiss: {
                MainActor.assumeIsolated { window?.close() }
            }
        ))
        host.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            host.topAnchor.constraint(equalTo: glass.topAnchor),
            host.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        w.contentView = glass
        window = w
        DockIconManager.windowDidOpen()

        // Start the modem audio. No fallback beep — if the asset is missing,
        // play nothing instead of triggering the system alert sound.
        if let sound = AudioBlob.load("s03") {
            player = sound
            sound.play()
        }

        let item = DispatchWorkItem {
            MainActor.assumeIsolated { window?.close() }
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + stageBreakpoints.autoDismiss, execute: item)

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
                dismissWorkItem?.cancel()
                dismissWorkItem = nil
                player?.stop()
                player = nil
                window = nil
                DockIconManager.windowDidClose()
            }
        }

        // `orderFrontRegardless` instead of `makeKeyAndOrderFront + NSApp.activate` —
        // the latter combo was triggering a macOS focus-shuffle alert sound
        // when the dialer popped up. The window still receives mouse clicks
        // on its stoplight buttons without being key.
        w.orderFrontRegardless()
    }
}

private enum DialStage: Int, CaseIterable {
    case dialing = 0
    case connecting
    case connected

    var label: String {
        switch self {
        case .dialing:    return "Dialing"
        case .connecting: return "Connecting…"
        case .connected:  return "Connected!"
        }
    }

    /// SF Symbols, paired (unfilled / filled). Unfilled shows before this
    /// stage is reached; filled shows once we're on or past it.
    var symbolNames: (unfilled: String, filled: String) {
        switch self {
        case .dialing:    return ("phone",            "phone.fill")
        case .connecting: return ("phone.connection", "phone.connection.fill")
        case .connected:  return ("globe.americas",   "globe.americas.fill")
        }
    }

    static func current(at t: TimeInterval) -> DialStage {
        if t < DialupSound.stageBreakpoints.dialingEnd { return .dialing }
        if t < DialupSound.stageBreakpoints.connectingEnd { return .connecting }
        return .connected
    }
}

private struct DialupView: View {
    let startDate: Date
    let onDismiss: () -> Void

    // Sampled from the bundled app icons.
    private let mojitoGreen  = Color(red: 0.45, green: 0.78, blue: 0.27)   // RGB 115/200/69
    private let mojitoOrange = Color(red: 0.95, green: 0.70, blue: 0.25)   // RGB 242/179/65

    /// One rhythmic value used for: window-edge → logo, logo → 3-up,
    /// 3-up → status, status → button, button → bottom, AND horizontal
    /// edges. All five vertical gaps match all four sides of padding.
    private let rhythm: CGFloat = 32

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let stage = DialStage.current(at: elapsed)

            VStack(spacing: rhythm) {
                logo
                stages(current: stage)
                statusBlock(stage: stage)
                hangUpButton
            }
            .padding(rhythm)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Don't fade into the connected state — the snap reads as
            // "handshake completed, you're online" rather than a gentle
            // arrival.
            .animation(stage == .connected ? nil : .easeInOut(duration: 0.35), value: stage)
        }
    }

    /// Cursive wordmark — bundled scrambled image rendered with native colors.
    private static let wordmark: NSImage? = ImageBlob.load("v06")

    @ViewBuilder
    private var logo: some View {
        if let img = Self.wordmark {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: 70)
        }
    }

    /// Three stage cards. Each card shows the unfilled SF Symbol until its
    /// stage is reached, then the filled variant. Active card pulses via
    /// the native symbol effect.
    private func stages(current: DialStage) -> some View {
        HStack(spacing: 18) {
            ForEach(DialStage.allCases, id: \.rawValue) { stage in
                stageCard(stage, current: current)
            }
        }
        .frame(height: 148)
    }

    @ViewBuilder
    private func stageCard(_ stage: DialStage, current: DialStage) -> some View {
        let reached = current.rawValue >= stage.rawValue
        let isActive = current == stage
        let symbol = reached ? stage.symbolNames.filled : stage.symbolNames.unfilled

        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isActive ? 0.22 : 0.10),
                                      lineWidth: 1)
                )

            stageIcon(symbol, isActive: isActive, reached: reached)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The connected card snaps on; earlier stages still crossfade.
        .animation(stage == .connected ? nil : .easeInOut(duration: 0.3), value: isActive)
    }

    @ViewBuilder
    private func stageIcon(_ symbol: String, isActive: Bool, reached: Bool) -> some View {
        let base = Image(systemName: symbol)
            .font(.system(size: 58, weight: .regular))

        if isActive {
            base
                .symbolEffect(.pulse, options: .repeating)
                .foregroundStyle(mojitoOrange)
        } else if reached {
            base.foregroundStyle(mojitoOrange.opacity(0.85))
        } else {
            base.foregroundStyle(mojitoOrange.opacity(0.35))
        }
    }

    /// Stage label — crossfades on stage change. No loader dots (the active
    /// card's pulsing icon already carries the in-flight feel).
    private func statusBlock(stage: DialStage) -> some View {
        Text(stage.label)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .contentTransition(.opacity)
            .id(stage)
    }

    /// "Hang up" — closes the window (and stops the modem sound via the
    /// willCloseNotification observer set up in `play()`).
    private var hangUpButton: some View {
        Button(action: onDismiss) {
            HStack(spacing: 6) {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Hang up")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.red.opacity(0.88))
            )
        }
        .buttonStyle(.plain)
    }
}
