import AppKit
import ApplicationServices

/// AX walk of the active browser tab. AppleScript needs per-app
/// automation permission and prompts on every browser — poor first-run UX.
@MainActor
enum BrowserURL {
    static func detect(bundleID: String?, pid: pid_t?) -> URL? {
        guard let bundleID, let pid else { return nil }
        guard isBrowser(bundleID: bundleID) else { return nil }

        let app = AXUIElementCreateApplication(pid)

        // Safari exposes AXURL on the web area.
        if let url = focusedWebAreaURL(in: app) { return url }

        if let raw = focusedAddressBarValue(in: app), let url = normalizedURL(from: raw) {
            return url
        }
        return nil
    }

    private static func isBrowser(bundleID: String) -> Bool {
        knownBrowserBundleIDs.contains(bundleID)
    }

    // Bundle IDs are opaque, so the obscure ones are named. detect() tries the
    // Safari web-area path then an address-bar fallback, so WebKit/Gecko entries
    // are best-effort; the Chromium path is the proven one.
    private static let knownBrowserBundleIDs: Set<String> = [
        // WebKit
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.kagi.kagimacOS",                       // Orion
        "com.kagi.kagimacOS.RC",                    // Orion RC
        "com.duckduckgo.macos.browser",             // DuckDuckGo
        "com.sigmaos.sigmaos.macos",                // SigmaOS

        // Chromium
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",
        "com.vivaldi.Vivaldi",
        "com.vivaldi.Vivaldi.snapshot",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.operasoftware.OperaAir",
        "com.operasoftware.OperaNext",              // Opera beta
        "com.operasoftware.OperaDeveloper",
        "company.thebrowser.Browser",               // Arc
        "company.thebrowser.dia",                   // Dia
        "net.imput.helium",                         // Helium
        "com.pushplaylabs.sidekick",                // Sidekick
        "ru.yandex.desktop.yandex-browser",         // Yandex
        "com.naver.Whale",                          // Naver Whale
        "io.wavebox.wavebox",                       // Wavebox

        // Gecko
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",                      // Firefox Nightly
        "app.zen-browser.zen",                      // Zen
        "one.ablaze.floorp",                        // Floorp
        "io.gitlab.librewolf-community.librewolf",  // LibreWolf
        "org.waterfoxproject.waterfox",             // Waterfox
        "net.mullvad.mullvadbrowser",               // Mullvad Browser
        "org.torproject.torbrowser",                // Tor Browser
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
