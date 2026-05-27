import AppKit
import ApplicationServices
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
/// - AX values are summarized structurally via `PickerContextStore`'s
///   `summarize(_:)` — never raw contents.
/// - Activity log values are clamped to 32 ASCII-printable chars at the
///   recording site, not here.
@MainActor
enum DebugReport {
    /// Maximum bytes emitted. Test enforces this; if a future addition
    /// blows past it the test will fail and force a re-tightening.
    static let maxSizeBytes = 8192

    static func markdown(now: Date = Date()) -> String {
        var out = ""
        out += "# Mojito debug report\n\n"
        out += mojitoSection(now: now)
        out += "\n"
        out += prefsSection()
        out += "\n"
        out += systemSection()
        out += "\n"
        out += lastPickerSection()
        out += "\n"
        out += activitySection(now: now)
        out += "\n"
        out += nowSection()
        out += "\n"
        out += footer(now: now)

        // Hard cap as a last line of defense — if some future
        // contributor adds an unbounded loop the report still pastes
        // into an issue without blowing it up.
        if out.utf8.count > maxSizeBytes {
            let cutoff = out.utf8.prefix(maxSizeBytes - 100)
            out = String(cutoff) ?? out
            out += "\n\n[truncated]\n"
        }
        return out
    }

    // MARK: - Sections

    private static func mojitoSection(now: Date) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let bundleID = Bundle.main.bundleIdentifier ?? "—"
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        let daysSince = daysSinceFirstLaunch(now: now)
        let ax = AXIsProcessTrusted()
        let inputMon = inputMonitoringGranted()
        let pausedUntil = UserDefaults.standard.object(forKey: PrefsKey.pausedUntil) as? TimeInterval
        let paused = (pausedUntil ?? 0) > now.timeIntervalSince1970

        var s = "## Mojito\n"
        s += "- bundleID: \(bundleID)\n"
        s += "- version: \(version) (\(build))\n"
        s += "- daysSinceFirstLaunch: \(daysSince)\n"
        s += "- permissions.accessibility: \(ax)\n"
        s += "- permissions.inputMonitoring: \(inputMon)\n"
        s += "- paused: \(paused)\n"
        return s
    }

    private static func prefsSection() -> String {
        let d = UserDefaults.standard
        // Sensitive collections — counts only.
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
        s += "- symbolsEnabled: \(bool(PrefsKey.symbolsEnabled, default: false))\n"
        s += "- symbolsRequireDoubleColon: \(bool(PrefsKey.symbolsRequireDoubleColon, default: false))\n"
        s += "- emoticonsEnabled: \(bool(PrefsKey.emoticonsEnabled, default: true))\n"
        s += "- gifSearchEnabled: \(bool(PrefsKey.gifSearchEnabled, default: true))\n"
        s += "- gifBypassExclusions: \(bool(PrefsKey.gifBypassExclusions, default: true))\n"
        s += "- launchAtLogin: \(bool(PrefsKey.launchAtLogin, default: false))\n"
        s += "- showMenuBarIcon: \(bool(PrefsKey.showMenuBarIcon, default: true))\n"
        s += "- skinTone: \(d.string(forKey: PrefsKey.skinTone) ?? "default")\n"
        s += "- totals.emojiInserted: \(d.integer(forKey: PrefsKey.totalEmojiInserted))\n"
        s += "- totals.symbolInserted: \(d.integer(forKey: PrefsKey.totalSymbolInserted))\n"
        s += "- totals.gifInserted: \(d.integer(forKey: PrefsKey.totalGifInserted))\n"
        return s
    }

    private static func systemSection() -> String {
        let pi = ProcessInfo.processInfo
        let osv = pi.operatingSystemVersion
        let arch = isAppleSilicon() ? "Apple Silicon" : "Intel"
        let locale = Locale.current.identifier
        let appearance = (NSApp?.effectiveAppearance.name.rawValue) ?? "—"
        let screens = NSScreen.screens
        let primary = screens.first?.frame ?? .zero

        var s = "## System\n"
        s += "- macOS: \(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)\n"
        s += "- arch: \(arch)\n"
        s += "- locale: \(locale)\n"
        s += "- appearance: \(appearance)\n"
        s += "- screens: \(screens.count)\n"
        s += "- primaryScreen: \(Int(primary.width))x\(Int(primary.height))\n"
        return s
    }

    private static func lastPickerSection() -> String {
        guard let snap = PickerContextStore.latest else {
            return "## Last picker context\n- (no picker activity this session)\n"
        }
        var s = "## Last picker context\n"
        s += "- frontmostBundleID: \(snap.frontmostBundleID ?? "—")\n"
        s += "- frontmostAppVersion: \(snap.frontmostAppVersion ?? "—")\n"
        s += "- focusedRole: \(snap.focusedRole ?? "—")\n"
        s += "- focusedSubrole: \(snap.focusedSubrole ?? "—")\n"
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
        s += "- AX attributes:\n"
        for attr in snap.attributes {
            let short = attr.name.replacingOccurrences(of: "AX", with: "").replacingOccurrences(of: "Attribute", with: "")
            if attr.present {
                s += "  - \(short): \(attr.summary ?? "<present>")\n"
            } else {
                s += "  - \(short): absent\n"
            }
        }
        return s
    }

    private static func activitySection(now: Date) -> String {
        let events = DebugRecorder.snapshot().suffix(50)
        guard let oldest = events.first else {
            return "## Activity log\n- (empty)\n"
        }
        var s = "## Activity log (last \(events.count))\n"
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
        // Mirrors PermissionsCoordinator's check at a distance — kept
        // here as a one-off read to avoid coupling the report to engine
        // lifecycle. Returns true if the process is allowed to listen
        // for HID input events.
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
}
