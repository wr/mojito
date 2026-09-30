import Foundation

/// A GIF search backend. Pages are 0-based everywhere in Mojito; each
/// provider maps that onto its own paging scheme.
enum GifProvider: String, CaseIterable {
    case giphy
    case klipy

    var displayName: String {
        switch self {
        case .giphy: return "GIPHY"
        case .klipy: return "KLIPY"
        }
    }

    var toggled: GifProvider { self == .giphy ? .klipy : .giphy }

    /// Resolved in priority order: `UserDefaults` override → launch
    /// environment → key baked in at build time (see `build_giphy_key.py`).
    var apiKey: String {
        let (prefsKey, envName, embedded): (String, String, String)
        switch self {
        case .giphy: (prefsKey, envName, embedded) = (PrefsKey.giphyApiKey, "GIPHY_API_KEY", EmbeddedGiphyKey.value)
        case .klipy: (prefsKey, envName, embedded) = (PrefsKey.klipyApiKey, "KLIPY_API_KEY", EmbeddedKlipyKey.value)
        }
        if let k = UserDefaults.standard.string(forKey: prefsKey), !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment[envName], !k.isEmpty { return k }
        return embedded
    }

    /// `region` is an ISO 3166 alpha-2 code; only KLIPY uses it, to rank
    /// results for the user's locale.
    func searchURL(key: String, query: String, pageSize: Int, page: Int, region: String?) -> URL? {
        switch self {
        case .giphy:
            var components = URLComponents(string: "https://api.giphy.com/v1/gifs/search")!
            components.queryItems = [
                URLQueryItem(name: "api_key", value: key),
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(page * pageSize)),
                URLQueryItem(name: "rating", value: "pg-13"),
                URLQueryItem(name: "bundle", value: "messaging_non_clips"),
            ]
            return components.url
        case .klipy:
            var components = URLComponents()
            components.scheme = "https"
            components.host = "api.klipy.com"
            components.path = "/api/v1/\(key)/gifs/search"
            // No `customer_id`: it's optional, and sending one would tie
            // searches to an install.
            var items = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page", value: String(page + 1)),
                URLQueryItem(name: "per_page", value: String(pageSize)),
                URLQueryItem(name: "content_filter", value: "medium"),
                URLQueryItem(name: "format_filter", value: "gif"),
            ]
            if let region { items.append(URLQueryItem(name: "locale", value: region)) }
            components.queryItems = items
            return components.url
        }
    }

    func parsePage(_ data: Data, pageSize: Int) -> GifPage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch self {
        case .giphy:
            guard let entries = json["data"] as? [[String: Any]] else { return nil }
            // Counted before decoding so one malformed entry can't end paging.
            return GifPage(assets: entries.compactMap(GifAsset.init(giphyJSON:)),
                           hasMore: entries.count >= pageSize)
        case .klipy:
            guard let body = json["data"] as? [String: Any],
                  let entries = body["data"] as? [[String: Any]]
            else { return nil }
            // Ad rows only appear when ad params are sent (we send none).
            let assets = entries
                .filter { ($0["type"] as? String) != "ad" }
                .compactMap(GifAsset.init(klipyJSON:))
            return GifPage(assets: assets, hasMore: (body["has_next"] as? Bool) ?? false)
        }
    }
}

struct GifPage {
    let assets: [GifAsset]
    let hasMore: Bool
}
