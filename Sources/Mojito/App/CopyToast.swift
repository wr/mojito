import AppKit
import SwiftUI

/// Brief "Copied to clipboard" HUD, shown when an emoji is copied instead of
/// typed (the browser opened where no text field was focused).
@MainActor
enum CopyToast {
    private static var panel: NSPanel?
    private static var dismissWork: DispatchWorkItem?

    static func show(_ glyph: String) {
        let hosting = NSHostingView(rootView: CopyToastView(glyph: glyph))
        let size = hosting.fittingSize
        let panel = panel(size: size)
        panel.appearance = NSApp.effectiveAppearance
        panel.contentView = hosting

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let origin = CGPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + visible.height * 0.22
            )
            panel.setFrame(CGRect(origin: origin, size: size), display: true)
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }

        dismissWork?.cancel()
        let work = DispatchWorkItem { dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    private static func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private static func panel(size: CGSize) -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // the SwiftUI capsule carries its own shadow
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.panel = panel
        return panel
    }
}

private struct CopyToastView: View {
    let glyph: String

    var body: some View {
        HStack(spacing: 9) {
            Text(glyph).font(.system(size: 22))
            Text("Copied to clipboard")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))
        .shadow(color: .black.opacity(0.22), radius: 9, y: 2)
        .padding(10)  // room for the shadow inside the panel
    }
}
