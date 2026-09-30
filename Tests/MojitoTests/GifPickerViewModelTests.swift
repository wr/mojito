import Foundation
import Testing
@testable import Mojito

@MainActor
struct GifPickerViewModelTests {

    @Test func pagesAreCountedNotOffsetByResultCount() async throws {
        // A page that comes back short (an ad skipped, a malformed entry
        // dropped) must not shift the next request back onto the same page.
        final class ShortPageSearcher: GifSearching {
            var pages: [Int] = []
            func search(query: String, pageSize: Int, page: Int,
                        completion: @escaping (Result<GifPage, GifSearchError>) -> Void) {
                pages.append(page)
                let assets = (0..<(pageSize - 1)).map { i in
                    GifAsset(id: "\(page)-\(i)",
                             thumbURL: URL(string: "https://example.com/t.gif")!,
                             originalURL: URL(string: "https://example.com/o.gif")!,
                             title: "")
                }
                completion(.success(GifPage(assets: assets, hasMore: true)))
            }
        }
        let searcher = ShortPageSearcher()
        let vm = GifPickerViewModel(searcher: searcher)
        vm.query = "cat"
        for _ in 0..<40 where searcher.pages.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        vm.loadMoreIfNeeded()
        #expect(searcher.pages == [0, 1])
    }
}
