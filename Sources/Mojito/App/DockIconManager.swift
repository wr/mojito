import AppKit

/// Promotes to `.regular` (dock icon + ⌘Tab) while any Settings/Onboarding
/// window is open; reverts to `.accessory` when the last one closes.
/// Ref-counted so closing one of multiple visible windows doesn't demote.
@MainActor
enum DockIconManager {
    private static var refCount = 0

    static func windowDidOpen() {
        refCount += 1
        if refCount == 1 {
            NSApp.setActivationPolicy(.regular)
        }
    }

    static func windowDidClose() {
        refCount = max(0, refCount - 1)
        if refCount == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
