import Foundation
import os.log

/// Thin Giphy search client. Reads the API key from (in priority order)
/// `UserDefaults[PrefsKey.giphyApiKey]`, the `GIPHY_API_KEY` environment
/// variable, or the bundled placeholder constant `defaultBetaKey`.
///
/// Get a beta key (free, 100 req/hr) at https://developers.giphy.com — then
/// either paste it below, set it as an env var when launching, or write it
/// to defaults:
///     defaults write ee.wells.Mojito.dev mojito.giphyApiKey "<your key>"
///
/// The bundled placeholder will not authenticate; the panel will show an
/// "API key required" message until a real key is configured.
@MainActor
final class GifSearcher {
    /// Replace with your own Giphy beta key, or leave blank and provide via
    /// UserDefaults / env var. Public-shared keys aren't a thing on Giphy
    /// anymore — every developer gets their own.
    private static let defaultBetaKey: String = ""

    private let log = OSLog(subsystem: "ee.wells.Mojito", category: "GifSearcher")
    private let session: URLSession
    private var inFlight: URLSessionDataTask?

    init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024,
                                   diskCapacity: 50 * 1024 * 1024,
                                   diskPath: "mojito-gif")
        config.timeoutIntervalForRequest = 8
        self.session = URLSession(configuration: config)
    }

    var apiKey: String {
        if let k = UserDefaults.standard.string(forKey: PrefsKey.giphyApiKey), !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["GIPHY_API_KEY"], !k.isEmpty { return k }
        return Self.defaultBetaKey
    }

    var hasKey: Bool { !apiKey.isEmpty }

    /// Cancels any in-flight request and starts a new one. Result handler
    /// fires on the main actor.
    func search(query: String, limit: Int = 9, completion: @escaping (Result<[GifAsset], GifSearchError>) -> Void) {
        inFlight?.cancel()
        inFlight = nil

        let key = apiKey
        guard !key.isEmpty else {
            completion(.failure(.missingApiKey))
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success([]))
            return
        }

        var components = URLComponents(string: "https://api.giphy.com/v1/gifs/search")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "rating", value: "pg-13"),
            URLQueryItem(name: "bundle", value: "messaging_non_clips"),
        ]
        guard let url = components.url else {
            completion(.failure(.badURL))
            return
        }

        let task = session.dataTask(with: url) { [weak self] data, response, error in
            if let error = error as NSError?, error.code == NSURLErrorCancelled { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.finish(data: data, response: response, error: error, completion: completion)
                }
            }
        }
        inFlight = task
        task.resume()
    }

    private func finish(data: Data?, response: URLResponse?, error: Error?,
                        completion: (Result<[GifAsset], GifSearchError>) -> Void) {
        if let error {
            os_log("GIF search failed: %{public}@", log: log, type: .info, "\(error)")
            completion(.failure(.network(error)))
            return
        }
        guard let http = response as? HTTPURLResponse else {
            completion(.failure(.badResponse))
            return
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                completion(.failure(.unauthorized))
            } else {
                completion(.failure(.httpStatus(http.statusCode)))
            }
            return
        }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]]
        else {
            completion(.failure(.badResponse))
            return
        }
        let assets = entries.compactMap(GifAsset.init(json:))
        completion(.success(assets))
    }
}

enum GifSearchError: Error {
    case missingApiKey
    case unauthorized
    case badURL
    case badResponse
    case httpStatus(Int)
    case network(Error)

    var userMessage: String {
        switch self {
        case .missingApiKey:
            return String(localized: "Add a Giphy API key to enable GIF search.")
        case .unauthorized:
            return String(localized: "Giphy rejected the API key.")
        case .badURL, .badResponse, .httpStatus:
            return String(localized: "Giphy responded with an unexpected result.")
        case .network:
            return String(localized: "Couldn't reach Giphy.")
        }
    }
}
