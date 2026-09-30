import Foundation

/// KLIPY GIF search: key resolution, request shape and response parsing.
/// Pages are 0-based in Mojito; KLIPY's are 1-based.
enum KlipyAPI {
    /// Resolved in priority order: `UserDefaults` override → launch
    /// environment → key baked in at build time (see `build_klipy_key.py`).
    static var apiKey: String {
        if let k = UserDefaults.standard.string(forKey: PrefsKey.klipyApiKey), !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["KLIPY_API_KEY"], !k.isEmpty { return k }
        return EmbeddedKlipyKey.value
    }

    /// `region` is an ISO 3166 alpha-2 code KLIPY uses to rank results for
    /// the user's locale.
    static func searchURL(key: String, query: String, pageSize: Int, page: Int, region: String?) -> URL? {
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

    static func parsePage(_ data: Data) -> GifPage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = json["data"] as? [String: Any],
              let entries = body["data"] as? [[String: Any]]
        else { return nil }
        // Ad rows only appear when ad params are sent (we send none).
        let assets = entries
            .filter { ($0["type"] as? String) != "ad" }
            .compactMap(GifAsset.init(klipyJSON:))
        return GifPage(assets: assets, hasMore: (body["has_next"] as? Bool) ?? false)
    }
}

struct GifPage {
    let assets: [GifAsset]
    let hasMore: Bool
}
