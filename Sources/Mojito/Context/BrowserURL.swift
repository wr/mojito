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
        // Per-object timeout + total deadline: either bound alone can be beaten (one slow node vs. many fast ones).
        let deadline = Date().addingTimeInterval(Self.walkBudget)

        // Most browsers expose the page URL as an `AXURL` attribute somewhere
        // under the focused window — Safari/WebKit on the `AXWebArea`, Chrome
        // and other Chromium browsers on a top-level `AXGroup`. Walking the
        // tree DFS for the first element that carries `AXURL` finds the
        // outermost page URL before any nested iframe.
        if let url = focusedURL(in: app, deadline: deadline) { return url }

        if let raw = focusedAddressBarValue(in: app, deadline: deadline),
           let url = normalizedURL(from: raw) {
            return url
        }
        return nil
    }

    /// Per-object AX timeout for every node touched in the walk, and a total
    /// wall-clock cap for the whole walk. Both are needed: the per-object timeout
    /// bounds a single hung node, the deadline bounds a deep tree of slow ones.
    private static let walkAXTimeout: Float = 0.1
    private static let walkBudget: TimeInterval = 0.25

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

    private static func focusedURL(in app: AXUIElement, deadline: Date) -> URL? {
        guard let window = focusedWindow(in: app) else { return nil }
        guard let element = findElement(under: window, depth: 10, deadline: deadline, match: { el in
            copyAttribute(el, attribute: "AXURL") != nil
        }) else { return nil }
        guard let value = copyAttribute(element, attribute: "AXURL") else { return nil }
        if let url = value as? URL { return url }
        if let str = value as? String { return URL(string: str) }
        return nil
    }

    private static func focusedAddressBarValue(in app: AXUIElement, deadline: Date) -> String? {
        guard let window = focusedWindow(in: app) else { return nil }
        guard let toolbar = findElement(role: "AXToolbar", under: window, depth: 10, deadline: deadline) else { return nil }
        guard let field = findAddressField(under: toolbar, deadline: deadline) else { return nil }
        return copyAttribute(field, attribute: kAXValueAttribute as String) as? String
    }

    private static func focusedWindow(in app: AXUIElement) -> AXUIElement? {
        guard let window = copyAttribute(app, attribute: kAXFocusedWindowAttribute as String),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return (window as! AXUIElement)
    }

    private static func findAddressField(under element: AXUIElement, deadline: Date) -> AXUIElement? {
        return findElement(under: element, depth: 4, deadline: deadline) { candidate in
            guard let role = copyAttribute(candidate, attribute: kAXRoleAttribute as String) as? String,
                  role == "AXTextField" else { return false }
            let desc = copyAttribute(candidate, attribute: kAXDescriptionAttribute as String) as? String ?? ""
            let title = copyAttribute(candidate, attribute: kAXTitleAttribute as String) as? String ?? ""
            let combined = (desc + " " + title).lowercased()
            return combined.contains("address") || combined.contains("url") || combined.contains("location")
        }
    }

    // MARK: - AX traversal helpers

    private static func findElement(role: String, under element: AXUIElement, depth: Int, deadline: Date) -> AXUIElement? {
        findElement(under: element, depth: depth, deadline: deadline) { candidate in
            (copyAttribute(candidate, attribute: kAXRoleAttribute as String) as? String) == role
        }
    }

    private static func findElement(
        under element: AXUIElement,
        depth: Int,
        deadline: Date,
        match: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        if depth < 0 { return nil }
        if Date() >= deadline { return nil }               // total-walk cap
        if match(element) { return element }
        guard let children = copyAttribute(element, attribute: kAXChildrenAttribute as String) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let hit = findElement(under: child, depth: depth - 1, deadline: deadline, match: match) {
                return hit
            }
        }
        return nil
    }

    private static func copyAttribute(_ element: AXUIElement, attribute: String) -> AnyObject? {
        // Pin THIS object's timeout — an AXUIElementSetMessagingTimeout only
        // applies to the object it's set on, so every node in the walk must set
        // its own or it inherits the looser process-wide default (W-557).
        AXUIElementSetMessagingTimeout(element, walkAXTimeout)
        var ref: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        return result == .success ? ref : nil
    }

    nonisolated fileprivate static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("://") { return URL(string: trimmed) }
        return URL(string: "https://" + trimmed)
    }
}

/// `.unavailable` means the resolve timed out — callers must keep the last good value, not overwrite it with nil.
enum BrowserURLResolution: Sendable {
    case resolved(URL?)
    case unavailable
}

/// URL cache for browsers whose tab URL is only readable via AppleScript (Arc).
/// `BrowserURL.detect` is called synchronously inside the CGEventTap callback,
/// so it can't run the AppleScript there — a slow Apple Event trips the tap
/// timeout and drops the keystroke (W-555).
///
/// Resolution: the hot-path read (`url(forBundleID:pid:)`) never does IPC — it
/// returns the last resolved value and schedules a refresh. The refresh runs the
/// AppleScript **off the main thread** on `resolveQueue`, via an `osascript`
/// subprocess (which sidesteps `NSAppleScript`'s main-thread requirement) with a
/// hard wall-clock bound. That matters for a genuinely hung Arc: the earlier
/// W-555 design ran `NSAppleScript` on the main thread, so a frozen Arc would
/// wedge Mojito's *entire* main thread — UI and event tap — until the Apple
/// Event timed out (up to ~2 min), turning "one browser hung" into "Mojito
/// hung" and dropping keystrokes the whole time (W-557). Off-thread + bounded,
/// a hung Arc only stalls this one worker, which is killed after `resolveBudget`;
/// the tap thread never blocks. Same spirit as `FocusedElementCache` (W-547).
/// A throttle keeps refreshes to at most one per second. Bounded staleness (≈
/// one keystroke, or one navigation until the next read/refresh) is fine for
/// per-site exclusion matching; the value is served only for the pid it was
/// resolved from, so it can't bleed across an app switch.
@MainActor
final class BrowserURLCache {
    static let shared = BrowserURLCache(
        observeActivations: true,
        minRefreshInterval: 1.0,
        now: { Date() },
        resolver: { BrowserURLCache.osascriptURL(bundleID: $0) }
    )

    typealias Resolver = @Sendable (String) -> BrowserURLResolution

    /// Off-main worker for the (potentially slow / hung) AppleScript resolve.
    private static let resolveQueue = DispatchQueue(
        label: "mojito.browserURL.resolve", qos: .userInitiated
    )

    /// Hard cap on a single resolve. A responsive Arc answers in tens of ms; a
    /// hung one is killed at this bound and reported as "no URL".
    private static let resolveBudget: DispatchTimeInterval = .milliseconds(800)

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
    private let minRefreshInterval: TimeInterval

    /// Seams. Production wires the real `osascript` resolver and wall clock;
    /// tests inject a stub resolver + controllable clock so the deferral,
    /// single-flight, throttle, and pid-guard are checkable without AppleScript
    /// or a real app switch (`observeActivations: false`). The resolver runs off
    /// the main thread, so it must be `@Sendable`.
    private let now: () -> Date
    private let resolver: Resolver

    init(
        observeActivations: Bool,
        minRefreshInterval: TimeInterval,
        now: @escaping () -> Date,
        resolver: @escaping Resolver
    ) {
        self.minRefreshInterval = minRefreshInterval
        self.now = now
        self.resolver = resolver
        guard observeActivations else { return }
        // Prefetch on activation so switching to Arc and immediately typing has
        // a warm URL rather than a first-keystroke miss. The closure refers to
        // `.shared` rather than capturing `self`, so it doesn't retain the
        // singleton (which lives for the app's lifetime anyway).
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

    /// Resolves the URL on a background worker, then publishes on the main actor.
    /// The resolve never runs inside the tap callback that calls `detect` — and,
    /// unlike the earlier main-thread version, never on the main thread at all —
    /// so even a hung Arc can't stall the tap or the UI. Single-flight (`refreshing`)
    /// plus the throttle keep at most one worker in flight per second.
    private func scheduleRefresh(bundleID: String, pid: pid_t, force: Bool) {
        guard !refreshing else { return }
        if !force, haveResult, let last = lastRefreshAt,
           now().timeIntervalSince(last) < minRefreshInterval {
            return
        }
        refreshing = true
        let resolve = resolver
        Self.resolveQueue.async { [weak self] in
            let outcome = resolve(bundleID)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch outcome {
                    case .resolved(let url):
                        self.cachedURL = url
                        self.cachedPID = pid
                        self.haveResult = true
                    case .unavailable:
                        // Keep the last good value: a transient stall must not
                        // erase a cached excluded-site URL. The pid guard in
                        // `url(...)` still prevents serving it across an app
                        // switch (a different pid reads as "no URL").
                        break
                    }
                    self.lastRefreshAt = self.now()
                    self.refreshing = false
                }
            }
        }
    }

    // osascript subprocess so it can be killed; temp file instead of Pipe to avoid the 64 KB buffer deadlock.
    private nonisolated static func osascriptURL(bundleID: String) -> BrowserURLResolution {
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mojito-arcurl-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outURL) }
        guard let outHandle = try? FileHandle(forWritingTo: outURL) else { return .unavailable }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application id \"\(bundleID)\" to return URL of active tab of front window",
        ]
        process.standardOutput = outHandle
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { try? outHandle.close(); return .unavailable }

        // Bound the wait: a hung Arc must not wedge this worker indefinitely.
        if done.wait(timeout: .now() + resolveBudget) == .timedOut {
            process.terminate()
            try? outHandle.close()
            return .unavailable                     // keep the last good value
        }
        try? outHandle.close()
        // Clean exit: read the file. A non-URL / empty output is a real "no URL".
        let raw = ((try? String(contentsOf: outURL, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .resolved(raw.isEmpty ? nil : BrowserURL.normalizedURL(from: raw))
    }
}
