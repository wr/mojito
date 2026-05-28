import Foundation
import os.log

/// Thin Giphy search client. Resolves the API key in priority order:
///   1. `UserDefaults[PrefsKey.giphyApiKey]` — user override.
///   2. `GIPHY_API_KEY` environment variable — developer override at launch.
///   3. `EmbeddedGiphyKey.value` — the key baked into the binary at build
///      time from `$GIPHY_API_KEY` or the gitignored `.env`. This is what
///      released builds use; fresh clones with no `.env` get an empty
///      string here and the panel shows "API key required".
@MainActor
final class GifSearcher {
    private let log = OSLog(subsystem: "ee.wells.Mojito", category: "GifSearcher")
    private var inFlight: URLSessionDataTask?

    /// Shared across search API calls and `AnimatedGifView` thumbnail loads
    /// so all GIF traffic populates one disk-backed `URLCache` — without
    /// this, thumbnails fall back to `URLCache.shared` (~10 MB system-wide)
    /// and evict almost immediately as cells scroll.
    nonisolated(unsafe) static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024,
                                   diskCapacity: 50 * 1024 * 1024,
                                   diskPath: "mojito-gif")
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config)
    }()

    var apiKey: String {
        if let k = UserDefaults.standard.string(forKey: PrefsKey.giphyApiKey), !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["GIPHY_API_KEY"], !k.isEmpty { return k }
        return EmbeddedGiphyKey.value
    }

    var hasKey: Bool { !apiKey.isEmpty }

    /// Cancels any in-flight request and starts a new one. Result handler
    /// fires on the main actor. `offset` drives pagination — the viewmodel
    /// bumps it to fetch successive pages as the user scrolls.
    func search(query: String, limit: Int = 24, offset: Int = 0,
                completion: @escaping (Result<[GifAsset], GifSearchError>) -> Void) {
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
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "rating", value: "pg-13"),
            URLQueryItem(name: "bundle", value: "messaging_non_clips"),
        ]
        guard let url = components.url else {
            completion(.failure(.badURL))
            return
        }

        let task = GifSearcher.session.dataTask(with: url) { [weak self] data, response, error in
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
