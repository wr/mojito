import AppKit
import SwiftUI

/// Windows 9x BSOD. Inverted "Mojito" pill + canonical VGA message,
/// blinking "Press any key to continue _" prompt. Dismiss is click or
/// Esc — a non-activating NSPanel can't grab global keys.
@MainActor
enum BlueScreen {
    private static var activeWindow: NSWindow?
    private static var unregister: (() -> Void)?
    private static var startupSound: NSSound?

    static func start() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        activeWindow?.orderOut(nil)
        activeWindow = nil
        startupSound?.stop()
        startupSound = nil

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = true
        panel.backgroundColor = NSColor(red: 0.0, green: 0.0, blue: 0.66, alpha: 1)
        panel.hasShadow = false
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        let dismiss = {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                startupSound?.stop()
                startupSound = nil
                unregister?()
                unregister = nil
                if activeWindow === panel { activeWindow = nil }
            }
        }

        let host = NSHostingView(rootView: BlueScreenView(bounds: frame.size, onDismiss: dismiss))
        host.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = host
        panel.orderFrontRegardless()
        activeWindow = panel
        unregister = EffectDismisser.register(anyKey: true, dismiss)

        // Compy 386 startup chirp (~1s) — boot-failure vibe.
        if let sound = AudioBlob.load("s15") {
            sound.volume = 0.8
            startupSound = sound
            sound.play()
        }
    }
}

private struct BlueScreenView: View {
    let bounds: CGSize
    let onDismiss: () -> Void

    /// VGA-ish gray, not pure white.
    private let bsodBlue = Color(red: 0.0, green: 0.0, blue: 0.66)
    private let bsodFG = Color(red: 0.85, green: 0.85, blue: 0.85)
    private let bsodHeaderBg = Color(red: 0.6, green: 0.6, blue: 0.6)

    /// 0 = collapsed-to-slit; 1 = full image. Drives the CRT power-on.
    @State private var poweredOn: Bool = false

    var body: some View {
        ZStack {
            // Without this, scaleY < 1 leaks the desktop through.
            Color.black.ignoresSafeArea()

            ZStack {
                bsodBlue
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer()
                        Text(verbatim: " Mojito ")
                            .font(.system(size: 22, weight: .regular, design: .monospaced))
                            .foregroundColor(bsodBlue)
                            .padding(.horizontal, 2)
                            .background(bsodHeaderBg)
                        Spacer()
                    }
                    .padding(.bottom, 20)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "A fatal exception 0E has occurred at 0xDEADBEEF:0xCAFEBABE in VXD")
                        Text(verbatim: "MOJITO(01) + 0xC0FFEE42. The current application will be terminated.")
                        Text(verbatim: " ")
                        Text(verbatim: "*   Press any key to terminate the current application.")
                        Text(verbatim: "*   Press  CTRL+ALT+DEL  again to restart your computer. You will")
                        Text(verbatim: "    lose any unsaved information in all applications.")
                        Text(verbatim: " ")
                        HStack {
                            Spacer()
                            blinkingPrompt
                            Spacer()
                        }
                    }
                    .font(.system(size: 22, weight: .regular, design: .monospaced))
                    .foregroundColor(bsodFG)
                }
                // Measure the longest line so the pill centers over it.
                .fixedSize(horizontal: true, vertical: false)
            }
            // CRT power-on: starts (0.8, 0.6), easeOutBack overshoot.
            .scaleEffect(
                x: poweredOn ? 1.0 : 0.8,
                y: poweredOn ? 1.0 : 0.6,
                anchor: .center
            )
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onAppear {
            // CSS `easeOutBack` — 1.56 Y control causes the overshoot.
            withAnimation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.22)) {
                poweredOn = true
            }
        }
    }

    private var blinkingPrompt: some View {
        TimelineView(.periodic(from: Date(), by: 0.45)) { context in
            let blink = Int(context.date.timeIntervalSinceReferenceDate / 0.45) % 2 == 0
            HStack(spacing: 0) {
                Text(verbatim: "Press any key to continue ")
                Text(verbatim: "_").opacity(blink ? 1 : 0)
            }
        }
    }
}
