import AppKit
import SwiftUI

/// "Connecting To Mojito Online…" — Tahoe-styled dial-up modem dialog.
/// Handshake plays while the window is open; closing stops it and an
/// auto-dismiss fires a few seconds after "Connected!".
@MainActor
enum DialupSound {
    fileprivate static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?
    private static var player: NSSound?
    private static var dismissWorkItem: DispatchWorkItem?

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

        // No fallback beep — better silent than system alert.
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

        // makeKeyAndOrderFront + NSApp.activate triggered macOS's
        // focus-shuffle alert sound. Stoplights still work without key.
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

    /// Filled once we're on or past this stage.
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

    @Environment(\.colorScheme) private var colorScheme

    // Sampled from the bundled app icons.
    private let mojitoGreen  = Color(red: 0.45, green: 0.78, blue: 0.27)   // RGB 115/200/69
    private let mojitoOrange = Color(red: 0.95, green: 0.70, blue: 0.25)   // RGB 242/179/65
    // Native SVG fill (#2E3192). Used in light mode; dark mode flips to white.
    private let wordmarkBlue = Color(red: 0x2E / 255.0, green: 0x31 / 255.0, blue: 0x92 / 255.0)

    /// All five vertical gaps + four-side padding share this value.
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
            // Connected snaps in — reads as "handshake done, online".
            .animation(stage == .connected ? nil : .easeInOut(duration: 0.35), value: stage)
        }
    }

    /// Bundled scrambled image, native colors. Marked as a template so
    /// SwiftUI's `.foregroundStyle` can re-tint the single-color SVG fill.
    private static let wordmark: NSImage? = {
        guard let image = ImageBlob.load("v06") else { return nil }
        image.isTemplate = true
        return image
    }()

    @ViewBuilder
    private var logo: some View {
        if let img = Self.wordmark {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: 70)
                .foregroundStyle(colorScheme == .dark ? Color.white : wordmarkBlue)
        }
    }

    /// Three stage cards. Active card pulses via symbolEffect.
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
        // Connected snaps; earlier stages crossfade.
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

    /// Stage label, crossfading. The pulsing icon carries the in-flight feel.
    private func statusBlock(stage: DialStage) -> some View {
        Text(stage.label)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .contentTransition(.opacity)
            .id(stage)
    }

    /// Closes the window; the willCloseNotification observer stops the sound.
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
