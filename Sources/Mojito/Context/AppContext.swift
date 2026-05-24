import AppKit
import ApplicationServices

struct ActiveContext {
    let bundleID: String?
    let processID: pid_t?
    let url: URL?
    /// When true, the engine must not begin capture — password fragments
    /// would leak into the picker UI and usage stats.
    let focusedFieldIsSecure: Bool
}

@MainActor
enum AppContextDetector {
    static func current() -> ActiveContext {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier
        let pid = app?.processIdentifier
        let url = BrowserURL.detect(bundleID: bundleID, pid: pid)
        let secure = focusedFieldIsSecure()
        return ActiveContext(
            bundleID: bundleID,
            processID: pid,
            url: url,
            focusedFieldIsSecure: secure
        )
    }

    /// True if AXSecureTextField, OR if AX is too broken to tell.
    /// False positives just mean the picker doesn't open in odd contexts;
    /// false negatives leak password fragments. Easy tradeoff.
    private static func focusedFieldIsSecure() -> Bool {
        let focused: AXUIElement
        if let cached = FocusedElementCache.shared.element {
            focused = cached
        } else {
            // Cache miss: no focused element means we're mid-transition;
            // allow capture rather than block.
            let system = AXUIElementCreateSystemWide()
            var ref: AnyObject?
            let status = AXUIElementCopyAttributeValue(
                system,
                kAXFocusedUIElementAttribute as CFString,
                &ref
            )
            guard status == .success, let element = ref else { return false }
            focused = element as! AXUIElement
        }

        var roleRef: AnyObject?
        let roleStatus = AXUIElementCopyAttributeValue(
            focused,
            kAXRoleAttribute as CFString,
            &roleRef
        )
        // Focused element but can't read its role — err secure.
        guard roleStatus == .success, let role = roleRef as? String else { return true }
        // String literal because `kAXSecureTextFieldRole` isn't reliably
        // bridged across SDK versions. Electron/web password inputs that
        // masquerade as AXTextField rely on the app/URL exclusion list.
        return role == "AXSecureTextField"
    }
}
