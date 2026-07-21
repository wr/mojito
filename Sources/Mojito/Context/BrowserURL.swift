import AppKit
import ApplicationServices

/// AX walk of the active browser tab. AppleScript needs per-app
/// automation permission and prompts on every browser — poor first-run UX.
@MainActor
enum BrowserURL {
    static func detect(bundleID: String?, pid: pid_t?) -> URL? {
        guard let bundleID, let pid else { return nil }
        guard isBrowser(bundleID: bundleID) else { return nil }

        // Arc suppresses the Chromium web-content a11y tree entirely — no
        // AXWebArea, no AXURL, and its address bar is a transient command bar
        // with no persistent AXTextField. The AX walk below always comes up nil
        // for it, so per-site exclusions can only be read via AppleScript. Both
        // of those cost matter here because `detect` runs inside the CGEventTap
        // callback (see `Engine.process`): the synchronous AppleScript Apple
        // Event AND the multi-node AX walk are each cross-process IPC that, on a
        // busy Arc, blow past the tap timeout — macOS then disables the tap and
        // drops the keystroke, which stalled Arc's command bar on every
        // word+terminator (W-555). So for Arc we skip the AX walk entirely and
        // serve the URL from an async cache (`BrowserURLCache`), which keeps the
        // AppleScript on the main thread — where NSAppleScript is supported —
        // but on its own run-loop turn, never inside the tap callback. Gated to
        // this one bundle ID: it's the only browser that needs AppleScript (Dia,
        // same vendor, exposes AXURL fine), and the first call triggers a
        // one-time Automation prompt we don't want to inflict elsewhere.
        if BrowserURLCache.appleScriptBundleIDs.contains(bundleID) {
            return BrowserURLCache.shared.url(forBundleID: bundleID, pid: pid)
        }

        let app = AXUIElementCreateApplication(pid)

        // Most browsers expose the page URL as an `AXURL` attribute somewhere
        // under the focused window — Safari/WebKit on the `AXWebArea`, Chrome
        // and other Chromium browsers on a top-level `AXGroup`. Walking the
        // tree DFS for the first element that carries `AXURL` finds the
        // outermost page URL before any nested iframe.
        if let url = focusedURL(in: app) { return url }

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

    private static func focusedURL(in app: AXUIElement) -> URL? {
        guard let window = focusedWindow(in: app) else { return nil }
        guard let element = findElement(under: window, depth: 10, match: { el in
            copyAttribute(el, attribute: "AXURL") != nil
        }) else { return nil }
        guard let value = copyAttribute(element, attribute: "AXURL") else { return nil }
        if let url = value as? URL { return url }
        if let str = value as? String { return URL(string: str) }
        return nil
    }

    private static func focusedAddressBarValue(in app: AXUIElement) -> String? {
        guard let window = focusedWindow(in: app) else { return nil }
        guard let toolbar = findElement(role: "AXToolbar", under: window, depth: 10) else { return nil }
        guard let field = findAddressField(under: toolbar) else { return nil }
        return copyAttribute(field, attribute: kAXValueAttribute as String) as? String
    }

    private static func focusedWindow(in app: AXUIElement) -> AXUIElement? {
        var ref: AnyObject?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref)
        guard result == .success, let window = ref,
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
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

    fileprivate static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("://") { return URL(string: trimmed) }
        return URL(string: "https://" + trimmed)
    }
}

/// URL cache for browsers whose tab URL is only readable via AppleScript (Arc).
/// `BrowserURL.detect` is called synchronously inside the CGEventTap callback,
/// so it can't run the AppleScript there — a slow Apple Event trips the tap
/// timeout and drops the keystroke (W-555). But `NSAppleScript` is documented
/// main-thread-only (Cocoa Thread Safety Summary), so it can't just be shoved
/// onto a background queue either.
///
/// Resolution: the hot-path read (`url(forBundleID:pid:)`) never does IPC — it
/// returns the last resolved value and schedules a refresh. The refresh runs
/// the AppleScript on the main thread, where it's supported, but via
/// `DispatchQueue.main.async` so it lands on its own run-loop turn rather than
/// inside the tap callback. A throttle keeps refreshes to at most one per
/// second, so the brief main-thread block can't recur per keystroke the way the
/// old synchronous call did. Same spirit as `FocusedElementCache` moving slow
/// IPC out of the tap path (W-547). Bounded staleness (≈ one keystroke, or one
/// navigation until the next read/refresh) is acceptable for per-site exclusion
/// matching; the value is only served for the pid it was resolved from, so it
/// can't bleed across an app switch.
@MainActor
final class BrowserURLCache {
    static let shared = BrowserURLCache()

    static let appleScriptBundleIDs: Set<String> = [
        "company.thebrowser.Browser",   // Arc
    ]

    /// Last resolved URL and the pid it belongs to. A `nil` url is a real
    /// answer (no window / denied Automation / non-URL value), cached as such
    /// via `haveResult` so we don't refetch it every keystroke.
    private var cachedURL: URL?
    private var cachedPID: pid_t?
    private var haveResult = false

    /// Single-flight: one refresh scheduled at a time, so a burst of reads (a
    /// word+terminator produces several) collapses to one AppleScript. Always
    /// cleared by the scheduled block, so a failed/timed-out script can't wedge
    /// it (the block runs regardless of the script's result).
    private var refreshing = false

    /// Throttles opportunistic per-read refreshes; app-activation refreshes
    /// bypass it (`force`) since a switch is infrequent and changes the pid.
    private var lastRefreshAt: Date?
    private static let minRefreshInterval: TimeInterval = 1.0

    private init() {
        // Prefetch on activation so switching to Arc and immediately typing has
        // a warm URL rather than a first-keystroke miss.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                guard let app = NSWorkspace.shared.frontmostApplication,
                      let bundleID = app.bundleIdentifier,
                      BrowserURLCache.appleScriptBundleIDs.contains(bundleID) else { return }
                BrowserURLCache.shared.scheduleRefresh(
                    bundleID: bundleID, pid: app.processIdentifier, force: true
                )
            }
        }
    }

    /// Cheap synchronous read for the hot path — no AppleScript, no AX IPC on
    /// this thread, so it never blocks the tap callback. Returns the cached URL
    /// only if it belongs to this pid, and schedules a throttled refresh so the
    /// next read reflects any navigation. A pid mismatch (or no result yet)
    /// reads as nil — exclusions treat that as "no URL", same as the AX paths
    /// coming up empty; the refresh fills it in for the following keystroke.
    func url(forBundleID bundleID: String, pid: pid_t) -> URL? {
        let value = (haveResult && cachedPID == pid) ? cachedURL : nil
        scheduleRefresh(bundleID: bundleID, pid: pid, force: false)
        return value
    }

    /// Resolves the URL on a *later* main-run-loop turn. `NSAppleScript` must
    /// run on the main thread, but never inside the tap callback that calls
    /// `detect` — `DispatchQueue.main.async` gives it its own turn, and the
    /// throttle keeps it rare enough that the brief main-thread block can't
    /// stall typing the way the per-keystroke synchronous call did.
    private func scheduleRefresh(bundleID: String, pid: pid_t, force: Bool) {
        guard !refreshing else { return }
        if !force, haveResult, let last = lastRefreshAt,
           Date().timeIntervalSince(last) < Self.minRefreshInterval {
            return
        }
        refreshing = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.cachedURL = Self.appleScriptURL(bundleID: bundleID)
                self.cachedPID = pid
                self.haveResult = true
                self.lastRefreshAt = Date()
                self.refreshing = false
            }
        }
    }

    /// `URL of active tab of front window` via AppleScript. Returns nil on any
    /// failure — no window, denied Automation permission, or a non-URL value —
    /// so callers fall through to "no URL" exactly as if AX had come up empty.
    /// Called only from `scheduleRefresh`'s main-thread block.
    private static func appleScriptURL(bundleID: String) -> URL? {
        let source = "tell application id \"\(bundleID)\" to return URL of active tab of front window"
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, let raw = result.stringValue else { return nil }
        return BrowserURL.normalizedURL(from: raw)
    }
}
