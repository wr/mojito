import AppKit
import SwiftUI

/// SwiftUI's `Settings` scene is flaky for `.accessory` apps on Tahoe —
/// `Selector("showSettingsWindow:")` stops resolving once the menu bar
/// isn't installed in the standard place.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(
        permissions: PermissionsCoordinator,
        exclusions: ExclusionStore,
        engine: Engine
    ) {
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

    func windowWillClose(_ notification: Notification) {
        // Detach so close() doesn't recurse into the closing window.
        let c = controller
        controller = nil
        c?.close()
        DockIconManager.windowDidClose()
    }
}
