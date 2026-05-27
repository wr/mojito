import AppKit
import ApplicationServices

/// Snapshot of the focused-element AX surface at the moment Mojito's
/// picker opens. Lives only in memory for this app session — the next
/// picker open overwrites it, and process exit clears it.
///
/// The report surfaces this as section 4 ("Last picker context"). It
/// answers the "what did the picker actually see?" question that
/// caret-positioning bugs need ground truth on. Values are summarized
/// structurally — for AX `kAXValue` we record `<string, length=N>`, not
/// the actual buffer text.
struct PickerContextSnapshot {
    struct AXAttribute {
        let name: String
        let present: Bool
        /// Shape-only summary, never raw contents. `nil` when `present == false`.
        let summary: String?
    }

    let capturedAt: Date
    let frontmostBundleID: String?
    let frontmostAppVersion: String?
    let focusedRole: String?
    let focusedSubrole: String?
    let attributes: [AXAttribute]
    let elementFrame: CGRect?
    let mouseLocation: CGPoint?
    let caretOutcome: String   // "axBounds" | "elementTopLeft" | "unavailable"
    let resolvedCaret: CGRect?
}

@MainActor
enum PickerContextStore {
    private(set) static var latest: PickerContextSnapshot?

    /// Called by Engine in the picker-open branches. Reads the focused
    /// element via `FocusedElementCache` (already main-thread, no IPC
    /// stall) plus a handful of caret-related AX attributes.
    static func capture(caretOutcome: String, resolvedCaret: CGRect?) {
        let app = NSWorkspace.shared.frontmostApplication
        let element = FocusedElementCache.shared.element

        let focusedRole = element.flatMap { copy($0, kAXRoleAttribute) as? String }
        let focusedSubrole = element.flatMap { copy($0, kAXSubroleAttribute) as? String }

        let regular = caretAttributes.map { key -> PickerContextSnapshot.AXAttribute in
            guard let element, let value = copy(element, key) else {
                return .init(name: key, present: false, summary: nil)
            }
            return .init(name: key, present: true, summary: summarize(value))
        }
        // Parameterized attributes can't be fetched without a valid
        // parameter, so presence is determined by enumerating the names
        // the element advertises. This is what distinguishes Ghostty
        // (advertises nothing) from TextEdit (advertises BoundsForRange).
        let parameterizedNames: Set<String> = element.flatMap(parameterizedNames(of:)) ?? []
        let parameterized = parameterizedCaretAttributes.map { key -> PickerContextSnapshot.AXAttribute in
            let present = parameterizedNames.contains(key)
            return .init(name: key, present: present, summary: present ? "<parameterized>" : nil)
        }
        let attrs = regular + parameterized

        let elementFrame: CGRect? = {
            guard let element,
                  let posRef = copy(element, kAXPositionAttribute),
                  let sizeRef = copy(element, kAXSizeAttribute) else { return nil }
            var origin = CGPoint.zero, size = CGSize.zero
            AXValueGetValue((posRef as! AXValue), .cgPoint, &origin)
            AXValueGetValue((sizeRef as! AXValue), .cgSize, &size)
            return CGRect(origin: origin, size: size)
        }()

        latest = PickerContextSnapshot(
            capturedAt: Date(),
            frontmostBundleID: app?.bundleIdentifier,
            frontmostAppVersion: app?.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String },
            focusedRole: focusedRole,
            focusedSubrole: focusedSubrole,
            attributes: attrs,
            elementFrame: elementFrame,
            mouseLocation: NSEvent.mouseLocation,
            caretOutcome: caretOutcome,
            resolvedCaret: resolvedCaret
        )
    }

    static func reset() { latest = nil }

    /// Regular (non-parameterized) AX attributes we probe at picker open.
    private static let caretAttributes: [String] = [
        kAXSelectedTextRangeAttribute as String,
        kAXInsertionPointLineNumberAttribute as String,
        kAXNumberOfCharactersAttribute as String,
        kAXVisibleCharacterRangeAttribute as String,
        kAXPositionAttribute as String,
        kAXSizeAttribute as String,
    ]

    /// Parameterized AX attributes — these need
    /// `AXUIElementCopyParameterizedAttributeValue` plus a valid
    /// parameter to fetch. For a presence-only diagnostic check, ask
    /// the element which parameterized attributes it advertises.
    /// `BoundsForRange` is the one that distinguishes a working caret
    /// app (TextEdit) from a broken one (Ghostty).
    private static let parameterizedCaretAttributes: [String] = [
        kAXBoundsForRangeParameterizedAttribute as String,
        kAXRangeForPositionParameterizedAttribute as String,
        kAXRangeForIndexParameterizedAttribute as String,
        kAXRangeForLineParameterizedAttribute as String,
    ]

    private static func copy(_ element: AXUIElement, _ key: String) -> AnyObject? {
        var ref: AnyObject?
        return AXUIElementCopyAttributeValue(element, key as CFString, &ref) == .success ? ref : nil
    }

    private static func parameterizedNames(of element: AXUIElement) -> Set<String> {
        var names: CFArray?
        guard AXUIElementCopyParameterizedAttributeNames(element, &names) == .success,
              let list = names as? [String] else { return [] }
        return Set(list)
    }

    /// Shape-only stringification. Never returns the raw value's contents.
    private static func summarize(_ value: AnyObject) -> String {
        if let s = value as? String {
            return "<string, length=\(s.count)>"
        }
        if let n = value as? NSNumber {
            // Bools come through as NSNumber too; distinguish via type encoding.
            if String(cString: n.objCType) == "c" {
                return "<bool, \(n.boolValue)>"
            }
            return "<number>"
        }
        if let arr = value as? [Any] {
            return "<array, count=\(arr.count)>"
        }
        if let dict = value as? [String: Any] {
            return "<dict, keys=\(dict.count)>"
        }
        if CFGetTypeID(value) == AXValueGetTypeID() {
            let axValue = value as! AXValue
            switch AXValueGetType(axValue) {
            case .cgPoint:    return "<AXValue cgPoint>"
            case .cgSize:     return "<AXValue cgSize>"
            case .cgRect:     return "<AXValue cgRect>"
            case .cfRange:    return "<AXValue cfRange>"
            default:          return "<AXValue>"
            }
        }
        return "<opaque>"
    }
}
