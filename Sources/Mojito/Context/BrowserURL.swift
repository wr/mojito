import AppKit
import ApplicationServices

/// Best-effort URL detection for the active browser tab.
///
/// Uses Accessibility to walk the focused window's address bar / web area instead of
/// AppleScript — AppleScript requires explicit per-app automation permission and
/// brings up a system prompt for every browser the user hits, which is a poor first-run UX.
@MainActor
enum BrowserURL {
    static func detect(bundleID: String?, pid: pid_t?) -> URL? {
        guard let bundleID, let pid else { return nil }
        guard isBrowser(bundleID: bundleID) else { return nil }

        let app = AXUIElementCreateApplication(pid)

        // Try the focused window's web area first (Safari exposes AXURL on the web area).
        if let url = focusedWebAreaURL(in: app) { return url }

        // Otherwise try to read the address bar value as a string.
        if let raw = focusedAddressBarValue(in: app), let url = normalizedURL(from: raw) {
            return url
        }
        return nil
    }

    private static func isBrowser(bundleID: String) -> Bool {
        knownBrowserBundleIDs.contains(bundleID)
    }

    private static let knownBrowserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.google.Chrome.beta",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",   // Arc
        "company.thebrowser.dia",       // Dia
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    private static func focusedWebAreaURL(in app: AXUIElement) -> URL? {
        guard let window = focusedWindow(in: app) else { return nil }
        guard let webArea = findElement(role: "AXWebArea", under: window, depth: 6) else { return nil }
        guard let value = copyAttribute(webArea, attribute: "AXURL") else { return nil }
        if let url = value as? URL { return url }
        if let str = value as? String { return URL(string: str) }
        return nil
    }

    private static func focusedAddressBarValue(in app: AXUIElement) -> String? {
        guard let window = focusedWindow(in: app) else { return nil }
        guard let toolbar = findElement(role: "AXToolbar", under: window, depth: 4) else { return nil }
        guard let field = findAddressField(under: toolbar) else { return nil }
        return copyAttribute(field, attribute: kAXValueAttribute as String) as? String
    }

    private static func focusedWindow(in app: AXUIElement) -> AXUIElement? {
        var ref: AnyObject?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref)
        guard result == .success, let window = ref else { return nil }
        return (window as! AXUIElement)
    }

    private static func findAddressField(under element: AXUIElement) -> AXUIElement? {
        // Look for an AXTextField with role description matching common address-bar names.
        return findElement(under: element, depth: 4) { candidate in
            guard let role = copyAttribute(candidate, attribute: kAXRoleAttribute as String) as? String,
                  role == "AXTextField" else { return false }
            let desc = copyAttribute(candidate, attribute: kAXDescriptionAttribute as String) as? String ?? ""
            let title = copyAttribute(candidate, attribute: kAXTitleAttribute as String) as? String ?? ""
            let combined = (desc + " " + title).lowercased()
            return combined.contains("address") || combined.contains("url") || combined.contains("location")
        }
    }

    // MARK: - AX traversal helpers

    private static func findElement(role: String, under element: AXUIElement, depth: Int) -> AXUIElement? {
        findElement(under: element, depth: depth) { candidate in
            (copyAttribute(candidate, attribute: kAXRoleAttribute as String) as? String) == role
        }
    }

    private static func findElement(
        under element: AXUIElement,
        depth: Int,
        match: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        if depth < 0 { return nil }
        if match(element) { return element }
        guard let children = copyAttribute(element, attribute: kAXChildrenAttribute as String) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let hit = findElement(under: child, depth: depth - 1, match: match) {
                return hit
            }
        }
        return nil
    }

    private static func copyAttribute(_ element: AXUIElement, attribute: String) -> AnyObject? {
        var ref: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        return result == .success ? ref : nil
    }

    private static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("://") { return URL(string: trimmed) }
        return URL(string: "https://" + trimmed)
    }
}
