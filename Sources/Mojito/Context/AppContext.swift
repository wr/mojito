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

    /// Controls/containers with no caret — a pick here has nowhere to go.
    /// Anything *not* listed (web areas, plain groups, unknown roles) leans
    /// toward editable: minimal browsers often hand back the web-view container
    /// instead of the focused field, and synthetic keystrokes still land there.
    private static let nonTextRoles: Set<String> = [
        "AXButton", "AXStaticText", "AXImage", "AXMenuItem", "AXMenuButton",
        "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXSlider", "AXLink",
        "AXList", "AXTable", "AXOutline", "AXScrollArea", "AXRow", "AXCell",
        "AXColumn", "AXToolbar", "AXTabGroup",
    ]

    /// True when the focused element can accept typed text. Biased toward
    /// `true` (the browser hotkey is explicit, and synthetic keystrokes land in
    /// fields AX can't fully describe); only no focused element at all, or a
    /// positively non-text control, reads as false.
    private static func focusedFieldIsEditable() -> Bool {
        guard let focused = resolveFocusedElement() else { return false }
        // Role first: a positively non-text element (e.g. a read-only label
        // that still exposes a selection range) has nowhere to type.
        if let role = copyString(focused, kAXRoleAttribute) {
            if nonTextRoles.contains(role) { return false }
            if editableRoles.contains(role) { return true }
        }
        // Settable value (native + most web/Electron inputs).
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return true
        }
        // A selectable text range = a caret (incl. WebKit text areas).
        var rangeRef: AnyObject?
        if AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success {
            return true
        }
        // Unreadable role or an opaque container — lean editable.
        return true
    }

    /// The focused element from the cache, falling back to a synchronous
    /// system-wide query. `nil` only when nothing is focused.
    private static func resolveFocusedElement() -> AXUIElement? {
        if let cached = FocusedElementCache.shared.element { return cached }
        let system = AXUIElementCreateSystemWide()
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let element = ref,
              CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        return (element as! AXUIElement)
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
