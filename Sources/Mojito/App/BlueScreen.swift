import AppKit
import SwiftUI

/// One of the discoverable effects. See `EasterEgg` for the
/// (opaque) identity; the trigger keyword is decoded at runtime from
/// `EggStrings` and not present in source.
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

        // Compy 386 startup chirp (~1s) — fires the moment the screen
        // appears for that authentic boot-failure vibe.
        if let sound = AudioBlob.load("s15") {
            startupSound = sound
            sound.play()
        }
    }
}

private struct BlueScreenView: View {
    let bounds: CGSize
    let onDismiss: () -> Void

    /// Period-correct VGA-ish foreground gray (not pure white).
    private let bsodBlue = Color(red: 0.0, green: 0.0, blue: 0.66)
    private let bsodFG = Color(red: 0.85, green: 0.85, blue: 0.85)
    private let bsodHeaderBg = Color(red: 0.6, green: 0.6, blue: 0.6)

    /// Body lines indented to match the reference image. `*` bullets,
    /// continuation lines aligned with the text-after-bullet column.
    /// The block is a single fixed-width VStack vertically and horizontally
    /// centered on screen; the "Windows" pill is centered relative to the
    /// body text block above it.
    var body: some View {
        ZStack {
            bsodBlue.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                // Inverted "Windows" pill — centered above the body block.
                HStack {
                    Spacer()
                    Text(" Mojito ")
                        .font(.system(size: 22, weight: .regular, design: .monospaced))
                        .foregroundColor(bsodBlue)
                        .padding(.horizontal, 2)
                        .background(bsodHeaderBg)
                    Spacer()
                }
                .padding(.bottom, 20)

                // Body text — left-aligned monospace lines.
                VStack(alignment: .leading, spacing: 6) {
                    Text("A fatal exception 0E has occurred at 0xDEADBEEF:0xCAFEBABE in VXD")
                    Text("MOJITO(01) + 0xC0FFEE42. The current application will be terminated.")
                    Text(" ")
                    Text("*   Press any key to terminate the current application.")
                    Text("*   Press  CTRL+ALT+DEL  again to restart your computer. You will")
                    Text("    lose any unsaved information in all applications.")
                    Text(" ")
                    HStack {
                        Spacer()
                        blinkingPrompt
                        Spacer()
                    }
                }
                .font(.system(size: 22, weight: .regular, design: .monospaced))
                .foregroundColor(bsodFG)
            }
            // The whole block — pill + body — is treated as one fixed-width
            // unit and centered both axes. Using `.fixedSize` lets SwiftUI
            // measure the natural width of the longest line so the pill
            // really does center over the body block.
            .fixedSize(horizontal: true, vertical: false)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
    }

    private var blinkingPrompt: some View {
        TimelineView(.periodic(from: Date(), by: 0.45)) { context in
            let blink = Int(context.date.timeIntervalSinceReferenceDate / 0.45) % 2 == 0
            HStack(spacing: 0) {
                Text("Press any key to continue ")
                Text("_").opacity(blink ? 1 : 0)
            }
        }
    }
}
