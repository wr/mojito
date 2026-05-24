import AppKit
import ApplicationServices

struct ActiveContext {
    let bundleID: String?
    let processID: pid_t?
    let url: URL?
    /// True if the focused AX element is a secure text field (password input).
    /// When true, the engine must not begin capture — typing `:` in a password
    /// field should not trigger the picker, render password fragments in our UI,
    /// or record usage based on subsequent keystrokes.
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

    /// Inspect the system-wide focused element. Returns true if it is an
    /// `AXSecureTextField` OR if AX is sufficiently broken that we can't tell.
    /// The safe default for an unknown field is "treat as secure" — false
    /// positives just mean the picker doesn't open in some odd contexts;
    /// false negatives expose password fragments in our UI. Easy tradeoff.
    ///
    /// Note: the engine already gates the CGEventTap on `permissions.allGranted`,
    /// so accessibility is normally available here. If AX still fails the
    /// element/role read, something is genuinely wrong with the focused app
    /// and bailing out (return true) is the prudent choice.
    private static func focusedFieldIsSecure() -> Bool {
        let focused: AXUIElement
        if let cached = FocusedElementCache.shared.element {
            focused = cached
        } else {
            // Cache miss (mid-transition, observer not yet attached) — do the
            // slow path. Empty result means no focused element, which during
            // transitions is benign; allow capture.
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
        // Have a focused element but can't read its role → unknown context,
        // err on the side of secure.
        guard roleStatus == .success, let role = roleRef as? String else { return true }
        // "AXSecureTextField" is the canonical role for password fields (the
        // bridged constant `kAXSecureTextFieldRole` isn't reliably exposed to
        // Swift across SDK versions). Some Electron/web inputs masquerade as
        // AXTextField — those we can't detect without more context, so we rely
        // on the app/URL exclusion list for now.
        return role == "AXSecureTextField"
    }
}
