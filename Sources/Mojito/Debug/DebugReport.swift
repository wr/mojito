import AppKit
import ApplicationServices
import Carbon
import Foundation
import IOKit.hid

/// Markdown debug report copied via About → "Copy debug info".
///
/// **Anonymization invariants** (also covered by `DebugReportTests`):
/// - No file paths, usernames, hostnames, MAC addresses, IPs.
/// - Never reads `usageCounts`, `easterEggsDiscovered`, `excludedBundleIDs`,
///   `excludedURLPatterns`, `giphyApiKey` contents — only counts / booleans.
/// - No absolute dates in the prefs section (relative "X days ago" only).
///   One UTC timestamp in the footer.
/// - AX values are summarized structurally — never raw contents.
/// - Activity log values are clamped at the recording site.
@MainActor
enum DebugReport {
    /// Hard cap. The bigger the report the more useful for diagnosis, but
    /// it still needs to fit in a paste. 32 KB is comfortable for issue
    /// bodies and LLM context windows.
    static let maxSizeBytes = 32_768

    /// Real process start time, fetched via `kinfo_proc` so it doesn't
    /// drift like a lazy `Date()` would (a `static let` initializes on
    /// first access, which here would be the *first* time someone clicks
    /// Copy Debug Info — not at launch).
    private static func processStart() -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        guard sysctl(&mib, UInt32(mib.count), &proc, &size, nil, 0) == 0 else { return nil }
        let sec = TimeInterval(proc.kp_proc.p_starttime.tv_sec)
        let usec = TimeInterval(proc.kp_proc.p_starttime.tv_usec) / 1_000_000
        return Date(timeIntervalSince1970: sec + usec)
    }

    static func markdown(engine: Engine? = nil, now: Date = Date()) -> String {
        var out = ""
        out += "# Mojito debug report\n\n"
        out += mojitoSection(engine: engine, now: now)
        out += "\n"
        out += buildSection()
        out += "\n"
        out += prefsSection()
        out += "\n"
        out += systemSection()
        out += "\n"
        out += databaseSection()
        out += "\n"
        out += updaterSection(now: now)
        out += "\n"
        out += lastPickerSection(now: now)
        out += "\n"
        out += activitySection(now: now)
        out += "\n"
        out += nowSection()
        out += "\n"
        out += footer(now: now)

        if out.utf8.count > maxSizeBytes {
            let cutoff = out.utf8.prefix(maxSizeBytes - 100)
            out = String(cutoff) ?? out
            out += "\n\n[truncated]\n"
        }
        return out
    }

    // MARK: - Sections

    private static func mojitoSection(engine: Engine?, now: Date) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let bundleID = Bundle.main.bundleIdentifier ?? "—"
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        let daysSince = daysSinceFirstLaunch(now: now)
        let ax = AXIsProcessTrusted()
        let inputMon = inputMonitoringGranted()
        let pausedUntil = UserDefaults.standard.object(forKey: PrefsKey.pausedUntil) as? TimeInterval
        let paused = (pausedUntil ?? 0) > now.timeIntervalSince1970
        let uptime = processStart().map { formatDuration(now.timeIntervalSince($0)) } ?? "—"

        var s = "## Mojito\n"
        s += "- bundleID: \(bundleID)\n"
        s += "- version: \(version) (\(build))\n"
        s += "- processUptime: \(uptime)\n"
        s += "- daysSinceFirstLaunch: \(daysSince)\n"
        s += "- permissions.accessibility: \(ax)\n"
        s += "- permissions.inputMonitoring: \(inputMon)\n"
        s += "- paused: \(paused)\n"
        if paused, let pausedUntil {
            s += "- pausedRemaining: \(formatDuration(pausedUntil - now.timeIntervalSince1970))\n"
        }
        if let engine {
            s += "- engine.active: \(engine.isActive)\n"
            s += "- triggerState: \(engine.triggerStateLabel)\n"
        }
        return s
    }

    private static func buildSection() -> String {
        var s = "## Build\n"
        #if DEBUG
        s += "- configuration: Debug\n"
        #else
        s += "- configuration: Release\n"
        #endif
        s += "- codeSigned: \(isCodeSigned())\n"
        s += "- sandboxed: \(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)\n"
        return s
    }

    private static func prefsSection() -> String {
        let d = UserDefaults.standard
        let usageTotal = ((d.dictionary(forKey: PrefsKey.usageCounts) as? [String: Int]) ?? [:])
            .values.reduce(0, +)
        let eggsCount = ((d.array(forKey: PrefsKey.easterEggsDiscovered) as? [String]) ?? []).count
        let bundleExcl = ((d.array(forKey: PrefsKey.excludedBundleIDs) as? [String]) ?? []).count
        let urlExcl = ((d.array(forKey: PrefsKey.excludedURLPatterns) as? [String]) ?? []).count
        let giphySet = !((d.string(forKey: PrefsKey.giphyApiKey)) ?? "").isEmpty

        var s = "## Prefs\n"
        s += "- usageCounts.total: \(usageTotal)\n"
        s += "- easterEggs.discoveredCount: \(eggsCount)\n"
        s += "- exclusions.bundleIDCount: \(bundleExcl)\n"
        s += "- exclusions.urlPatternCount: \(urlExcl)\n"
        s += "- giphyApiKey.set: \(giphySet)\n"
        s += "- useFrequencyBoost: \(bool(PrefsKey.useFrequencyBoost, default: true))\n"
        s += "- emoticonsEnabled: \(bool(PrefsKey.emoticonsEnabled, default: true))\n"
        s += "- gifBypassExclusions: \(bool(PrefsKey.gifBypassExclusions, default: true))\n"
        s += "- launchAtLogin: \(bool(PrefsKey.launchAtLogin, default: false))\n"
        s += "- showMenuBarIcon: \(bool(PrefsKey.showMenuBarIcon, default: true))\n"
        s += "- skinTone: \(d.string(forKey: PrefsKey.skinTone) ?? "default")\n"
        s += "- totals.emojiInserted: \(d.integer(forKey: PrefsKey.totalEmojiInserted))\n"
        s += "- totals.symbolInserted: \(d.integer(forKey: PrefsKey.totalSymbolInserted))\n"
        s += "- totals.gifInserted: \(d.integer(forKey: PrefsKey.totalGifInserted))\n"
        s += "- totals.emoticonInserted: \(d.integer(forKey: PrefsKey.totalEmoticonInserted))\n"
        // Trigger strings are config, not user content — safe to include.
        let triggers = TriggerConfigStore.load(defaults: d)
        for t in triggers.all {
            s += "- triggers.\(t.mode.rawValue): '\(t.open)' enabled=\(t.enabled)\n"
        }
        return s
    }

    private static func systemSection() -> String {
        let pi = ProcessInfo.processInfo
        let osv = pi.operatingSystemVersion
        let arch = isAppleSilicon() ? "Apple Silicon" : "Intel"
        let locale = Locale.current.identifier
        let preferred = Locale.preferredLanguages.prefix(4).joined(separator: ", ")
        let appearance = (NSApp?.effectiveAppearance.name.rawValue) ?? "—"
        let screens = NSScreen.screens

        var s = "## System\n"
        s += "- macOS: \(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)\n"
        s += "- arch: \(arch)\n"
        s += "- locale: \(locale)\n"
        s += "- preferredLanguages: \(preferred)\n"
        s += "- inputSource: \(activeInputSourceID() ?? "—")\n"
        s += "- appearance: \(appearance)\n"
        s += "- thermalState: \(thermalStateString(pi.thermalState))\n"
        s += "- processorCount: \(pi.processorCount)\n"
        s += "- physicalMemoryGB: \(pi.physicalMemory / 1_073_741_824)\n"
        s += "- screens: \(screens.count)\n"
        for (i, screen) in screens.enumerated() {
            let f = screen.frame
            let scale = screen.backingScaleFactor
            let refresh = screen.maximumFramesPerSecond
            s += "  - screen[\(i)]: \(Int(f.width))x\(Int(f.height)) scale=\(scale) refresh=\(refresh)Hz\n"
        }
        return s
    }

    private static func databaseSection() -> String {
        var s = "## Database\n"
        s += "- emoji.count: \(EmojiDatabase.shared.all.count)\n"
        s += "- symbols.count: \(SymbolsDatabase.indexed().count)\n"
        return s
    }

    private static func updaterSection(now: Date) -> String {
        // Sparkle stores these in our UserDefaults under stable keys
        // documented in SUConstants.h (SULastCheckTimeKey etc.).
        var s = "## Updater\n"
        let lastCheck = UserDefaults.standard.object(forKey: "SULastCheckTime") as? Date
        s += "- lastCheck: \(lastCheck.map { "-\(formatDuration(now.timeIntervalSince($0))) ago" } ?? "never")\n"
        let interval = UserDefaults.standard.object(forKey: "SUScheduledCheckInterval") as? TimeInterval
        s += "- checkInterval: \(interval.map { formatDuration($0) } ?? "default")\n"
        let autoCheck = UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true
        s += "- automaticChecks: \(autoCheck)\n"
        return s
    }

    private static func lastPickerSection(now: Date) -> String {
        guard let snap = PickerContextStore.latest else {
            return "## Last picker context\n- (no picker activity this session)\n"
        }
        var s = "## Last picker context\n"
        s += "- capturedAt: -\(formatDuration(now.timeIntervalSince(snap.capturedAt))) ago\n"
        s += "- frontmostBundleID: \(snap.frontmostBundleID ?? "—")\n"
        s += "- frontmostAppVersion: \(snap.frontmostAppVersion ?? "—")\n"
        s += "- focusedRole: \(snap.focusedRole ?? "—")\n"
        s += "- focusedSubrole: \(snap.focusedSubrole ?? "—")\n"
        if !snap.roleChain.isEmpty {
            s += "- roleChain: \(snap.roleChain.joined(separator: " ← "))\n"
        }
        if let titleLen = snap.windowTitleLength {
            s += "- windowTitleLength: \(titleLen)\n"
        }
        s += "- caretOutcome: \(snap.caretOutcome)\n"
        if let frame = snap.elementFrame {
            s += "- elementFrame: \(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.size.width))x\(Int(frame.size.height))\n"
        }
        if let m = snap.mouseLocation {
            s += "- mouseLocation: \(Int(m.x)),\(Int(m.y))\n"
        }
        if let r = snap.resolvedCaret {
            s += "- resolvedCaret: \(Int(r.origin.x)),\(Int(r.origin.y)) \(Int(r.size.width))x\(Int(r.size.height))\n"
        }
        s += "- curated attributes:\n"
        for attr in snap.attributes {
            let short = attr.name.replacingOccurrences(of: "AX", with: "").replacingOccurrences(of: "Attribute", with: "")
            if attr.present {
                s += "  - \(short): \(attr.summary ?? "<present>")\n"
            } else {
                s += "  - \(short): absent\n"
            }
        }
        if !snap.allAttributeNames.isEmpty {
            s += "- all attrs: \(snap.allAttributeNames.sorted().joined(separator: ", "))\n"
        }
        if !snap.allParameterizedAttributeNames.isEmpty {
            s += "- all paramAttrs: \(snap.allParameterizedAttributeNames.sorted().joined(separator: ", "))\n"
        }
        return s
    }

    private static func activitySection(now: Date) -> String {
        // Action events get the lion's share; focus changes are capped so a
        // session of heavy app-switching can't crowd them out. Merge the two
        // streams back into chronological order for reading.
        let actions = DebugRecorder.snapshot().suffix(85)
        let focus = DebugRecorder.focusSnapshot().suffix(15)
        let events = (actions + focus).sorted { $0.timestamp < $1.timestamp }
        guard let oldest = events.first else {
            return "## Activity log\n- (empty)\n"
        }
        var s = "## Activity log (\(actions.count) action, \(focus.count) focus)\n"
        for event in events {
            let dt = event.timestamp.timeIntervalSince(oldest.timestamp)
            let meta = event.metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            let metaPart = meta.isEmpty ? "" : " \(meta)"
            s += "- [+\(String(format: "%.2fs", dt))] \(event.category.rawValue).\(event.kind)\(metaPart)\n"
        }
        return s
    }

    private static func nowSection() -> String {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "—"
        let element = FocusedElementCache.shared.element
        let role: String = {
            guard let element else { return "—" }
            var ref: AnyObject?
            let st = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref)
            return (st == .success ? (ref as? String) : nil) ?? "—"
        }()
        var s = "## Now\n"
        s += "- frontmostBundleID: \(bundleID)\n"
        s += "- focusedRole: \(role)\n"
        s += "- focusedElementCached: \(element != nil)\n"
        return s
    }

    private static func footer(now: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return "_Generated \(fmt.string(from: now)) UTC_\n"
    }

    // MARK: - Helpers

    private static func bool(_ key: String, default defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }

    private static func daysSinceFirstLaunch(now: Date) -> Int {
        let ts = UserDefaults.standard.object(forKey: PrefsKey.firstLaunchDate) as? TimeInterval ?? now.timeIntervalSince1970
        let delta = now.timeIntervalSince1970 - ts
        return max(0, Int(delta / 86_400))
    }

    private static func inputMonitoringGranted() -> Bool {
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private static func isAppleSilicon() -> Bool {
        var ret: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &ret, &size, nil, 0) == 0 {
            return ret == 1
        }
        return false
    }

    private static func isCodeSigned() -> Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        return SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess
    }

    private static func activeInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private static func thermalStateString(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }
}
