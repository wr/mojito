import Foundation
import os.log

@MainActor
protocol GifSearching: AnyObject {
    /// Cancels any in-flight request and starts a new one. `page` is 0-based.
    func search(query: String, pageSize: Int, page: Int,
                completion: @escaping (Result<GifPage, GifSearchError>) -> Void)
}

/// KLIPY search client; request shape and parsing live on `KlipyAPI`.
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

        let key = KlipyAPI.apiKey
        guard !key.isEmpty else {
            completion(.failure(.missingApiKey))
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success(GifPage(assets: [], hasMore: false)))
            return
        }

        let region = Locale.current.region?.identifier.lowercased()
        guard let url = KlipyAPI.searchURL(key: key, query: trimmed, pageSize: pageSize,
                                           page: page, region: region) else {
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
                        completion: (Result<GifPage, GifSearchError>) -> Void) {
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
        guard let data, let page = KlipyAPI.parsePage(data) else {
            completion(.failure(.badResponse))
            return
        }
        completion(.success(page))
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
            return String(localized: "Add a KLIPY API key to enable GIF search.")
        case .unauthorized:
            return String(localized: "KLIPY rejected the API key.")
        case .badURL, .badResponse, .httpStatus:
            return String(localized: "KLIPY responded with an unexpected result.")
        case .network:
            return String(localized: "Couldn't reach KLIPY.")
        }
    }
}
