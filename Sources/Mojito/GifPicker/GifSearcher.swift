import Foundation
import os.log

@MainActor
protocol GifSearching: AnyObject {
    /// Cancels any in-flight request and starts a new one. `page` is 0-based.
    func search(query: String, pageSize: Int, page: Int,
                completion: @escaping (Result<GifPage, GifSearchError>) -> Void)
}

/// GIF search client for the provider picked in Settings; request shape and
/// parsing live on `GifProvider`.
@MainActor
final class GifSearcher: GifSearching {
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

    func search(query: String, pageSize: Int, page: Int,
                completion: @escaping (Result<GifPage, GifSearchError>) -> Void) {
        inFlight?.cancel()
        inFlight = nil

        // Read per search, so a provider switched in Settings applies to the
        // next query.
        let provider = GifProvider.current
        let key = provider.apiKey
        guard !key.isEmpty else {
            completion(.failure(.missingApiKey(provider)))
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success(GifPage(assets: [], hasMore: false)))
            return
        }

        guard let url = provider.searchURL(key: key, query: trimmed, pageSize: pageSize, page: page) else {
            completion(.failure(.badURL(provider)))
            return
        }

        let task = GifSearcher.session.dataTask(with: url) { [weak self] data, response, error in
            if let error = error as NSError?, error.code == NSURLErrorCancelled { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.finish(provider: provider, pageSize: pageSize, data: data, response: response,
                                 error: error, completion: completion)
                }
            }
        }
        inFlight = task
        task.resume()
    }

    private func finish(provider: GifProvider, pageSize: Int, data: Data?, response: URLResponse?,
                        error: Error?, completion: (Result<GifPage, GifSearchError>) -> Void) {
        if let error {
            // Domain and code only: a URLError's description embeds the
            // request URL, which carries the search text and the API key.
            let nsError = error as NSError
            os_log("GIF search failed: %{public}@ %ld", log: log, type: .info, nsError.domain, nsError.code)
            completion(.failure(.network(provider, error)))
            return
        }
        guard let http = response as? HTTPURLResponse else {
            completion(.failure(.badResponse(provider)))
            return
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                completion(.failure(.unauthorized(provider)))
            } else if http.statusCode == 429 {
                completion(.failure(.rateLimited(provider)))
            } else {
                completion(.failure(.httpStatus(provider, http.statusCode)))
            }
            return
        }
        guard let data, let page = provider.parsePage(data, pageSize: pageSize) else {
            completion(.failure(.badResponse(provider)))
            return
        }
        completion(.success(page))
    }
}

enum GifSearchError: Error {
    case missingApiKey(GifProvider)
    case unauthorized(GifProvider)
    /// Per-key quotas are tight on GIPHY's free keys (and KLIPY test keys).
    case rateLimited(GifProvider)
    case badURL(GifProvider)
    case badResponse(GifProvider)
    case httpStatus(GifProvider, Int)
    case network(GifProvider, Error)

    var provider: GifProvider {
        switch self {
        case .missingApiKey(let p), .unauthorized(let p), .rateLimited(let p), .badURL(let p),
             .badResponse(let p), .httpStatus(let p, _), .network(let p, _):
            return p
        }
    }

    var userMessage: String {
        let name = provider.displayName
        switch self {
        case .missingApiKey:
            return String(localized: "Add a \(name) API key to enable GIF search.")
        case .unauthorized:
            return String(localized: "\(name) rejected the API key.")
        case .rateLimited:
            return String(localized: "\(name) is limiting searches right now. Try again in a few minutes.")
        case .badURL, .badResponse, .httpStatus:
            return String(localized: "\(name) responded with an unexpected result.")
        case .network:
            return String(localized: "Couldn't reach \(name).")
        }
    }
}
