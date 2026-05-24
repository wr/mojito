import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(permissions: PermissionsCoordinator) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = OnboardingRoot()
            .environmentObject(permissions)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to \(AppInfo.displayName)"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        // Size THEN center — `center()` uses current size for the origin.
        window.setContentSize(NSSize(width: 600, height: 520))
        window.center()
        window.delegate = OnboardingWindowDelegate.shared
        OnboardingWindowDelegate.shared.bind(controller: self)

        self.window = window
        DockIconManager.windowDidOpen()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}

@MainActor
final class OnboardingWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowDelegate()
    private weak var controller: OnboardingWindowController?

    func bind(controller: OnboardingWindowController) {
        self.controller = controller
    }

    func windowWillClose(_ notification: Notification) {
        // Detach so `controller.close()` doesn't recurse into the
        // already-closing window.
        let c = controller
        controller = nil
        c?.close()
        DockIconManager.windowDidClose()
    }
}
