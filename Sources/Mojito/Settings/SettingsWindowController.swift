import AppKit
import SwiftUI

/// Imperative window controller for the Settings window. We don't use SwiftUI's `Settings`
/// scene because it's flaky for `.accessory` apps in macOS Tahoe — the
/// `Selector("showSettingsWindow:")` trick stops resolving once the menu bar isn't installed
/// in the standard place.
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
        // Title is set dynamically from `SettingsRoot` based on the current
        // sidebar selection (About → "About", General → "General", etc.).
        window.title = "Settings"
        // Unified-toolbar look (matches System Settings on Tahoe):
        //  - .fullSizeContentView lets content extend behind the title-bar
        //    strip so scrolling pushes it under the translucent material.
        //  - titlebarAppearsTransparent stays FALSE: keeping the native
        //    title-bar material is what produces the scroll-under blur. With
        //    it true the title-bar area becomes fully transparent and there's
        //    nothing to blur the content with — that was the hard edge.
        //  - .unified toolbar style + NSToolbar with at least one item makes
        //    AppKit render the unified material across the whole strip.
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
        // Detach so close() doesn't recurse into the window that's already closing.
        let c = controller
        controller = nil
        c?.close()
        // DockIconManager will drop the activation policy back to .accessory
        // if this was the last visible non-menubar window.
        DockIconManager.windowDidClose()
    }
}
