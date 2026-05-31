import AppKit
import ApplicationServices

struct ActiveContext {
    let bundleID: String?
    let processID: pid_t?
    let url: URL?
    /// When true, the engine must not begin capture — password fragments
    /// would leak into the picker UI and usage stats.
    let focusedFieldIsSecure: Bool
    /// Whether the focused element accepts typed text. When false, the `:`
    /// trigger stays inert (nothing to autocomplete into) and emoji picks are
    /// copied to the clipboard instead of synthesized as keystrokes.
    let focusedFieldIsEditable: Bool
}

@MainActor
enum AppContextDetector {
    static func current() -> ActiveContext {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier
        let pid = app?.processIdentifier
        let url = BrowserURL.detect(bundleID: bundleID, pid: pid)
        return ActiveContext(
            bundleID: bundleID,
            processID: pid,
            url: url,
            focusedFieldIsSecure: focusedFieldIsSecure(),
            focusedFieldIsEditable: focusedFieldIsEditable()
        )
    }

    /// True if AXSecureTextField, OR if AX is too broken to tell.
    /// False positives just mean the picker doesn't open in odd contexts;
    /// false negatives leak password fragments. Easy tradeoff.
    private static func focusedFieldIsSecure() -> Bool {
        // No focused element = mid-transition; allow capture rather than block.
        guard let focused = resolveFocusedElement() else { return false }
        guard let role = copyString(focused, kAXRoleAttribute) else { return true }
        // String literal because `kAXSecureTextFieldRole` isn't reliably
        // bridged across SDK versions. Electron/web password inputs that
        // masquerade as AXTextField rely on the app/URL exclusion list.
        return role == "AXSecureTextField"
    }

    /// Text inputs whose value isn't reported as settable still count.
    private static let editableRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXSecureTextField",
    ]

    /// True when the focused element looks like it accepts typed text.
    /// Errs toward `true` when the element exists but is opaque (don't break
    /// quirky-AX text views); only a positively non-editable element — or no
    /// focused element at all — reads as false.
    private static func focusedFieldIsEditable() -> Bool {
        guard let focused = resolveFocusedElement() else { return false }
        // Strongest signal: a settable value (native + most web/Electron inputs).
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return true
        }
        guard let role = copyString(focused, kAXRoleAttribute) else { return true }
        return editableRoles.contains(role)
    }

    /// The focused element from the cache, falling back to a synchronous
    /// system-wide query. `nil` only when nothing is focused.
    private static func resolveFocusedElement() -> AXUIElement? {
        if let cached = FocusedElementCache.shared.element { return cached }
        let system = AXUIElementCreateSystemWide()
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let element = ref else { return nil }
        return (element as! AXUIElement)
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
