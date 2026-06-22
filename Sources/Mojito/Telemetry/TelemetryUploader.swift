import Foundation
import os.log

/// Builds and sends Mojito's once-a-day anonymous aggregate.
///
/// Gating (all must hold): telemetry enabled (opt-out, default on), the
/// one-time consent notice has been seen, and we haven't already uploaded
/// today (UTC). The payload carries no identifier and no timestamp; the
/// server discards the IP. On a 2xx the pending deltas are cleared so the
/// next day starts fresh. Failures are silent — the deltas survive and
/// retry next launch. See mojito.wells.ee/stats.
@MainActor
final class TelemetryUploader {
    static let shared = TelemetryUploader()
    private init() {}

    private let log = OSLog(subsystem: "ee.wells.Mojito", category: "Telemetry")

    /// Custom domain fronting the Cloudflare Worker. Must match the worker's
    /// route (see `stats-worker/`). The server never stores the IP.
    private let endpoint = URL(string: "https://stats.mojito.wells.ee/ingest")!
    private let schemaVersion = 1

    static func utcDay(_ now: Date = Date()) -> Int { Int(now.timeIntervalSince1970 / 86_400) }

    // Debug builds never upload — keeps dev pings out of production stats.
    private static let uploadsEnabled: Bool = {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }()

    func uploadIfDue() {
        let defaults = UserDefaults.standard
        guard Self.uploadsEnabled,
              TelemetryStore.isEnabled,
              defaults.bool(forKey: PrefsKey.telemetryConsentSeen),
              defaults.integer(forKey: PrefsKey.telemetryLastUploadDay) != Self.utcDay()
        else { return }

        let payload = makePayload(pending: TelemetryStore.snapshotPending())
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 10

        let task = URLSession.shared.dataTask(with: request) { [log] _, response, error in
            if let error { os_log("upload failed: %{public}@", log: log, type: .info, "\(error)"); return }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    TelemetryStore.clearPending()
                    UserDefaults.standard.set(Self.utcDay(), forKey: PrefsKey.telemetryLastUploadDay)
                }
            }
        }
        task.resume()
    }

    // MARK: - Payload

    private func makePayload(pending: TelemetryStore.Pending) -> [String: Any] {
        var payload: [String: Any] = [
            "v": schemaVersion,
            "os": osMajor(),
            "arch": arch(),
            "lang": language(),
            "skinTone": UserDefaults.standard.string(forKey: PrefsKey.skinTone) ?? "default",
            "features": features(),
            "totals": [
                "emoji": pending.emojiTotal,
                "symbol": pending.symbol,
                "gif": pending.gif,
                "emoticon": pending.emoticon,
                "quickAccess": pending.quickAccess,
            ],
            "eggs": pending.eggs,
        ]
        if let app = appVersion() { payload["app"] = app }
        // Quick Access favorites: how many of the 8 slots are pinned, plus the
        // pinned hexcodes for the public "top favorites" rollup. Hexcodes are
        // the same already-public emoji codepoints we send in `emoji`; symbol
        // pins (`SYM_…`) are dropped so only real emoji reach the histogram.
        let favorites = pinnedFavoriteHexcodes()
        payload["favoritesCount"] = favorites.count
        if !favorites.isEmpty { payload["favorites"] = favorites }
        if !pending.emoji.isEmpty {
            // Mirrors MAX_EMOJI_PER_PING in stats-worker/src/index.js — the
            // server drops everything past it, so trim client-side keeping
            // the highest counts; also bounds the body across failed days.
            let maxEmojiPerPing = 300
            var emoji = pending.emoji
            if emoji.count > maxEmojiPerPing {
                emoji = Dictionary(uniqueKeysWithValues:
                    emoji.sorted { $0.value > $1.value }.prefix(maxEmojiPerPing).map { ($0.key, $0.value) })
            }
            payload["emoji"] = emoji
        }
        return payload
    }

    private func features() -> [String: Bool] {
        let triggers = TriggerConfigStore.load()
        let def = TriggerConfig.default
        let triggersCustom = triggers.emoji != def.emoji
            || triggers.symbols != def.symbols
            || triggers.gif != def.gif
            || triggers.quickAccess != def.quickAccess
        return [
            // The emoji trigger can now be disabled, so its on/off state is a
            // real adoption signal rather than an always-true constant.
            "emoji": triggers.emoji.enabled,
            "symbols": triggers.symbols.enabled,
            // Kept for back-compat: now reflects the symbols *trigger* being on.
            "symbolsDoubleColon": triggers.symbols.enabled,
            "emoticons": bool(PrefsKey.emoticonsEnabled, true),
            "arrows": bool(PrefsKey.arrowConversionEnabled, true),
            "gifSearch": triggers.gif.enabled,
            "frequencyBoost": bool(PrefsKey.useFrequencyBoost, true),
            "launchAtLogin": bool(PrefsKey.launchAtLogin, false),
            "quickAccess": triggers.quickAccess.enabled,
            "menuBarIcon": bool(PrefsKey.showMenuBarIcon, true),
            "easterEggs": bool(PrefsKey.eggsEnabled, true),
            // Whether *any* trigger string differs from the shipped defaults —
            // one combined customization-adoption signal, no strings sent.
            "triggersCustom": triggersCustom,
            // Per-mode customization, kept for the debug/internal view.
            "emojiTriggerCustom": triggers.emoji != def.emoji,
            "symbolsTriggerCustom": triggers.symbols != def.symbols,
            "gifTriggerCustom": triggers.gif != def.gif,
            "quickAccessTriggerCustom": triggers.quickAccess != def.quickAccess,
        ]
    }

    /// Pinned Quick Access slots, as real emoji hexcodes. Empty (`""`) auto
    /// slots and symbol pins (`SYM_…`, which aren't emoji) are dropped.
    private func pinnedFavoriteHexcodes() -> [String] {
        let raw = (UserDefaults.standard.array(forKey: PrefsKey.quickAccessSlots) as? [String]) ?? []
        return raw.filter { !$0.isEmpty && !$0.hasPrefix("SYM_") }
    }

    // MARK: - Environment (all coarse, marginal)

    private func appVersion() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private func osMajor() -> String {
        String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    private func arch() -> String {
        var ret: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &ret, &size, nil, 0) == 0, ret == 1 { return "arm64" }
        return "x86_64"
    }

    private func language() -> String {
        Locale.current.language.languageCode?.identifier ?? "und"
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }
}
