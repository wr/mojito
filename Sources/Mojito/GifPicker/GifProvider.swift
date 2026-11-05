import Foundation

/// Where `:::` searches. KLIPY is the default and ships with a key baked into
/// the build; GIPHY runs on the user's own key, entered in Settings → General.
/// Pages are 0-based everywhere in Mojito; each provider maps that onto its
/// own paging scheme.
enum GifProvider: String, CaseIterable, Identifiable {
    case klipy
    case giphy

    static let `default`: GifProvider = .klipy

    /// The provider picked in Settings. An unknown stored value (a provider a
    /// later build dropped) falls back to the default.
    static var current: GifProvider { selected(in: .standard) }

    static func selected(in defaults: UserDefaults) -> GifProvider {
        defaults.string(forKey: PrefsKey.gifProvider).flatMap(GifProvider.init(rawValue:)) ?? .default
    }

    var id: String { rawValue }

    /// Brand name, also the attribution both providers' terms ask for
    /// ("Search KLIPY", "Powered by GIPHY"). Never localized.
    var displayName: String {
        switch self {
        case .klipy: return "KLIPY"
        case .giphy: return "GIPHY"
        }
    }

    var apiKey: String {
        switch self {
        case .klipy: return KlipyAPI.apiKey
        case .giphy: return GiphyAPI.apiKey
        }
    }

    func searchURL(key: String, query: String, pageSize: Int, page: Int, locale: Locale = .current) -> URL? {
        switch self {
        case .klipy:
            return KlipyAPI.searchURL(key: key, query: query, pageSize: pageSize, page: page,
                                      region: locale.region?.identifier.lowercased())
        case .giphy:
            return GiphyAPI.searchURL(key: key, query: query, pageSize: pageSize, page: page,
                                      language: GiphyAPI.language(for: locale))
        }
    }

    func parsePage(_ data: Data, pageSize: Int) -> GifPage? {
        switch self {
        case .klipy: return KlipyAPI.parsePage(data)
        case .giphy: return GiphyAPI.parsePage(data, pageSize: pageSize)
        }
    }
}
