import AppKit

/// Toggles the app's activation policy based on visible non-menubar windows.
///
/// `LSUIElement: true` keeps Mojito out of the dock by default. When the user
/// opens Settings or Onboarding we promote to `.regular` so they get a real
/// dock icon and the app appears in ⌘Tab — the natural macOS feel for a
/// window-bearing app. When the last such window closes we drop back to
/// `.accessory` and the dock icon disappears.
///
/// Reference-counted so multiple simultaneous windows behave correctly: if
/// Settings is already open and Onboarding opens, closing Settings alone
/// doesn't kick us back to accessory mode.
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
