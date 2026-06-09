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
            ],
            "eggs": pending.eggs,
        ]
        if let app = appVersion() { payload["app"] = app }
        if !pending.emoji.isEmpty {
            // The server keeps at most 300 emoji per ping; trimming here also
            // bounds the request body if pending has grown across failed days.
            var emoji = pending.emoji
            if emoji.count > 300 {
                emoji = Dictionary(uniqueKeysWithValues:
                    emoji.sorted { $0.value > $1.value }.prefix(300).map { ($0.key, $0.value) })
            }
            payload["emoji"] = emoji
        }
        return payload
    }

    private func features() -> [String: Bool] {
        [
            "symbols": bool(PrefsKey.symbolsEnabled, false),
            "symbolsDoubleColon": bool(PrefsKey.symbolsRequireDoubleColon, false),
            "emoticons": bool(PrefsKey.emoticonsEnabled, true),
            "arrows": bool(PrefsKey.arrowConversionEnabled, true),
            "gifSearch": bool(PrefsKey.gifSearchEnabled, true),
            "frequencyBoost": bool(PrefsKey.useFrequencyBoost, true),
            "launchAtLogin": bool(PrefsKey.launchAtLogin, false),
            "quickAccess": bool(PrefsKey.quickAccessEnabled, true),
            "menuBarIcon": bool(PrefsKey.showMenuBarIcon, true),
        ]
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
