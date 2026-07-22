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
    /// The focused AX element the field checks above were answered from —
    /// cache when warm, fresh system-wide query otherwise. Capture snapshots
    /// must use this, not the cache directly: right after an app switch the
    /// cache is intentionally nil while its background seed is in flight, and
    /// a nil snapshot would read as "opened with no focused field".
    let focusedElement: AXUIElement?
}

@MainActor
enum AppContextDetector {
    /// Every AX query below is a synchronous cross-process call made from inside
    /// the CGEventTap callback, which runs on the main thread (see `KeyMonitor` /
    /// `Engine`). A hung or beach-balling frontmost app makes those calls block;
    /// with the process-wide 0.5s messaging timeout, a handful of them in a row
    /// can blow past the ~1s tap timeout — macOS then disables the tap and drops
    /// the keystroke (W-547 for Safari lag, W-555 for Arc, generalized in W-557).
    /// So the tap-path queries are pinned to a much tighter per-element timeout:
    /// a stale/partial context just means the picker briefly declines to open,
    /// never a dropped keystroke. Real local AX answers in single-digit ms, so
    /// this only bites a genuinely unresponsive app — exactly when we must bail.
    static let tapAXTimeout: Float = 0.1

    /// Pins `element` to the tight tap-path timeout so a query against a hung app
    /// can't stall the tap callback. Best-effort; a failure just leaves the
    /// process-wide default in place.
    private static func boundToTapTimeout(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, tapAXTimeout)
    }

    static func current() -> ActiveContext {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier
        let pid = app?.processIdentifier
        let url = BrowserURL.detect(bundleID: bundleID, pid: pid)
        // Resolve once and reuse — each fallback resolution is a synchronous
        // cross-process AX call.
        let focused = resolveFocusedElement()
        // Bound the follow-up secure/editable attribute reads: they hit the
        // element's owning (possibly hung) app on the tap thread.
        if let focused { boundToTapTimeout(focused) }
        return ActiveContext(
            bundleID: bundleID,
            processID: pid,
            url: url,
            focusedFieldIsSecure: focusedFieldIsSecure(focused),
            focusedFieldIsEditable: focusedFieldIsEditable(focused),
            focusedElement: focused
        )
    }

    /// True if AXSecureTextField, OR if AX is too broken to tell.
    /// False positives just mean the picker doesn't open in odd contexts;
    /// false negatives leak password fragments. Easy tradeoff.
    private static func focusedFieldIsSecure(_ focused: AXUIElement?) -> Bool {
        // No focused element = mid-transition; allow capture rather than block.
        guard let focused else { return false }
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
    private static func focusedFieldIsEditable(_ focused: AXUIElement?) -> Bool {
        guard let focused else { return false }
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
        boundToTapTimeout(system)
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
