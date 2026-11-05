import Foundation

/// GIPHY GIF search: key resolution, request shape and response parsing.
/// No GIPHY key ships with Mojito — GIPHY issues keys per app, with a
/// per-key rate limit — so search runs on the user's own key.
enum GiphyAPI {
    /// The key from Settings, else the launch environment. Empty means GIF
    /// search asks for one.
    static var apiKey: String { apiKey(in: .standard, environment: ProcessInfo.processInfo.environment) }

    static func apiKey(in defaults: UserDefaults, environment: [String: String]) -> String {
        let saved = (defaults.string(forKey: PrefsKey.giphyApiKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty { return saved }
        return environment["GIPHY_API_KEY"] ?? ""
    }

    /// `language` is one of GIPHY's regional-content codes (see `language(for:)`).
    static func searchURL(key: String, query: String, pageSize: Int, page: Int, language: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.giphy.com"
        components.path = "/v1/gifs/search"
        // No `random_id`: it's optional, and sending one would tie searches
        // to an install.
        var items = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "offset", value: String(page * pageSize)),
            URLQueryItem(name: "rating", value: "pg-13"),
            URLQueryItem(name: "bundle", value: "messaging_non_clips"),
        ]
        if let language { items.append(URLQueryItem(name: "lang", value: language)) }
        components.queryItems = items
        return components.url
    }

    static func parsePage(_ data: Data, pageSize: Int) -> GifPage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]]
        else { return nil }
        let assets = entries.compactMap(GifAsset.init(giphyJSON:))
        // Paged off the raw entry count, so one undecodable entry can't end
        // paging early.
        let hasMore: Bool
        if let pagination = json["pagination"] as? [String: Any],
           let total = pagination["total_count"] as? Int,
           let offset = pagination["offset"] as? Int {
            hasMore = !entries.isEmpty && offset + entries.count < total
        } else {
            hasMore = entries.count >= pageSize
        }
        return GifPage(assets: assets, hasMore: hasMore)
    }

    /// GIPHY ranks regional content by language. It takes plain ISO 639-1
    /// codes plus `zh-CN` / `zh-TW` and the legacy `iw` for Hebrew; anything
    /// else (and English, the default) sends nothing.
    static func language(for locale: Locale) -> String? {
        guard let code = locale.language.languageCode?.identifier else { return nil }
        switch code {
        case "en":
            return nil
        case "zh":
            let traditional = locale.language.script?.identifier == "Hant"
                || ["TW", "HK", "MO"].contains(locale.region?.identifier ?? "")
            return traditional ? "zh-TW" : "zh-CN"
        case "he":
            return "iw"
        default:
            return supportedLanguages.contains(code) ? code : nil
        }
    }

    private static let supportedLanguages: Set<String> = [
        "ar", "bn", "cs", "da", "de", "es", "fa", "fi", "fr", "hi", "hu", "id",
        "it", "ja", "ko", "ms", "nl", "no", "pl", "pt", "ro", "ru", "sv", "th",
        "tl", "tr", "uk", "vi",
    ]
}
