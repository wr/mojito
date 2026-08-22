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
    /// Whether the cache had a resolved classification when this context was
    /// built. False = the field checks fell back to their fail-closed defaults
    /// (secure=true, editable=false) because the off-thread classify hadn't
    /// published yet. Diagnostics only.
    let focusedFieldHaveInfo: Bool
    /// Raw AXRole the classification was read from, or nil. Diagnostics only.
    let focusedRole: String?
    /// The focused AX element the field checks above were answered from.
    /// Capture snapshots must use this, not the cache directly: right after an
    /// app switch the cache is intentionally nil while its background seed is in
    /// flight, and a nil snapshot would read as "opened with no focused field".
    let focusedElement: AXUIElement?
}

@MainActor
enum AppContextDetector {
    // Tap callback: all reads must be cache-hits — no synchronous cross-process IPC; a hung app stalls past the ~1s timeout and macOS drops the keystroke.
    static func current() -> ActiveContext {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier
        let pid = app?.processIdentifier
        let url = BrowserURL.detect(bundleID: bundleID, pid: pid)

        let cache = FocusedElementCache.shared
        let secure: Bool
        let editable: Bool
        let haveInfo = cache.haveFieldInfo
        let role = cache.focusedRole
        if cache.haveFieldInfo {
            secure = cache.focusedIsSecure
            editable = cache.focusedIsEditable
        } else {
            // Classification not resolved yet (mid app-switch / mid focus-move).
            // Fail closed: never begin capture on an unclassified field — it
            // might be a password field the off-thread classify hasn't reached.
            secure = true
            editable = false
        }
        return ActiveContext(
            bundleID: bundleID,
            processID: pid,
            url: url,
            focusedFieldIsSecure: secure,
            focusedFieldIsEditable: editable,
            focusedFieldHaveInfo: haveInfo,
            focusedRole: role,
            focusedElement: cache.element
        )
    }

    /// Classifies a focused element as (secure, editable). `nonisolated` so
    /// `FocusedElementCache` can run it on its background seed queue — these are
    /// synchronous cross-process AX calls and must never run on the tap thread.
    /// The caller pins a messaging timeout on `element` first.
    nonisolated static func classify(_ element: AXUIElement) -> (secure: Bool, editable: Bool, role: String?) {
        (secure: isSecure(element), editable: isEditable(element), role: copyString(element, kAXRoleAttribute))
    }

    /// True if AXSecureTextField, OR if AX is too broken to tell (fail closed —
    /// a false positive just declines the picker; a false negative leaks
    /// password fragments).
    private nonisolated static func isSecure(_ focused: AXUIElement) -> Bool {
        // A missing role means AX is too broken to tell — fail closed.
        guard let role = copyString(focused, kAXRoleAttribute) else { return true }
        // "AXSecureTextField" is a *subrole*, not a role (there is no
        // kAXSecureTextFieldRole). Native NSSecureTextField and Chromium/WebKit
        // <input type=password> all report role AXTextField with this subrole,
        // so matching the subrole is what actually catches password fields —
        // across native, Electron, and web. Load-bearing now that we enable
        // Electron/web AX trees (W-572): those fields used to be invisible and
        // leaned on the exclusion list; the subrole check protects them
        // directly. Role kept as a defensive OR at zero cost.
        return role == "AXSecureTextField"
            || copyString(focused, kAXSubroleAttribute) == "AXSecureTextField"
    }

    /// Text inputs whose value isn't reported as settable still count.
    private nonisolated static let editableRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXSecureTextField",
    ]

    /// Controls/containers with no caret — a pick here has nowhere to go.
    /// Anything *not* listed (web areas, plain groups, unknown roles) leans
    /// toward editable: minimal browsers often hand back the web-view container
    /// instead of the focused field, and synthetic keystrokes still land there.
    private nonisolated static let nonTextRoles: Set<String> = [
        "AXButton", "AXStaticText", "AXImage", "AXMenuItem", "AXMenuButton",
        "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXSlider", "AXLink",
        "AXList", "AXTable", "AXOutline", "AXScrollArea", "AXRow", "AXCell",
        "AXColumn", "AXToolbar", "AXTabGroup",
    ]

    /// True when the focused element can accept typed text. Biased toward
    /// `true` (the browser hotkey is explicit, and synthetic keystrokes land in
    /// fields AX can't fully describe); only a positively non-text control reads
    /// as false.
    private nonisolated static func isEditable(_ focused: AXUIElement) -> Bool {
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

    private nonisolated static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
