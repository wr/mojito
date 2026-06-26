import AppKit
import SwiftUI

/// SwiftUI's `Settings` scene is flaky for `.accessory` apps on Tahoe —
/// `Selector("showSettingsWindow:")` stops resolving once the menu bar
/// isn't installed in the standard place.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private weak var engine: Engine?

    /// While Settings is key, suspend the global event tap so it doesn't fight
    /// `KeyboardShortcuts.Recorder` (and any open browser) for keystrokes.
    func setKey(_ isKey: Bool) {
        engine?.setMonitorSuspended(isKey)
    }

    func show(
        permissions: PermissionsCoordinator,
        exclusions: ExclusionStore,
        engine: Engine
    ) {
        self.engine = engine
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = SettingsRoot()
            .environmentObject(permissions)
            .environmentObject(exclusions)
            .environmentObject(engine)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        // SettingsRoot rewrites the title per sidebar selection.
        window.title = "Settings"
        // Unified-toolbar look (System Settings on Tahoe):
        //  - `fullSizeContentView` lets content scroll behind the title bar.
        //  - `titlebarAppearsTransparent` stays FALSE — the native title-bar
        //    material is what produces the scroll-under blur.
        //  - `.unified` + a non-empty NSToolbar renders the unified material
        //    across the whole strip.
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier: "ee.wells.Mojito.SettingsToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.setContentSize(NSSize(width: 700, height: 500))
        window.center()
        window.delegate = SettingsWindowDelegate.shared
        SettingsWindowDelegate.shared.bind(controller: self)

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
final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowDelegate()
    private weak var controller: SettingsWindowController?

    func bind(controller: SettingsWindowController) {
        self.controller = controller
    }

    func windowDidBecomeKey(_ notification: Notification) {
        controller?.setKey(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        controller?.setKey(false)
    }

    func windowWillClose(_ notification: Notification) {
        // Detach so close() doesn't recurse into the closing window.
        let c = controller
        controller = nil
        c?.setKey(false)
        c?.close()
        DockIconManager.windowDidClose()
    }
}
