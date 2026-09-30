import Foundation
import Testing
@testable import Mojito

/// Provider switching in `GifPickerViewModel`: Tab re-runs the current query
/// against the other provider, flipping back reuses that provider's results
/// instead of spending another request, and the choice sticks.
@MainActor
struct GifPickerViewModelTests {

    private final class FakeSearcher: GifSearching {
        struct Call: Equatable { let provider: GifProvider; let query: String; let page: Int }
        var calls: [Call] = []

        func search(provider: GifProvider, query: String, pageSize: Int, page: Int,
                    completion: @escaping (Result<GifPage, GifSearchError>) -> Void) {
            calls.append(Call(provider: provider, query: query, page: page))
            let asset = GifAsset(id: "\(provider.rawValue)-\(query)-\(page)",
                                 thumbURL: URL(string: "https://example.com/t.gif")!,
                                 originalURL: URL(string: "https://example.com/o.gif")!,
                                 title: query)
            completion(.success(GifPage(assets: [asset], hasMore: false)))
        }
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "mojito.tests.gif.\(UUID().uuidString)")!
    }

    /// Sets the query and waits out the view model's typing debounce.
    private func type(_ q: String, into vm: GifPickerViewModel, searcher: FakeSearcher) async throws {
        let before = searcher.calls.count
        vm.query = q
        for _ in 0..<40 where searcher.calls.count == before {
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(searcher.calls.count > before)
    }

    @Test func defaultsToGiphy() {
        let vm = GifPickerViewModel(searcher: FakeSearcher(), defaults: freshDefaults())
        #expect(vm.provider == .giphy)
    }

    @Test func toggleSearchesOtherProviderWithSameQuery() async throws {
        let searcher = FakeSearcher()
        let vm = GifPickerViewModel(searcher: searcher, defaults: freshDefaults())
        try await type("cat", into: vm, searcher: searcher)

        vm.toggleProvider()

        #expect(vm.provider == .klipy)
        #expect(searcher.calls.last == .init(provider: .klipy, query: "cat", page: 0))
        #expect(vm.results.map(\.id) == ["klipy-cat-0"])
    }

    @Test func togglingBackReusesEarlierResultsWithoutRequest() async throws {
        let searcher = FakeSearcher()
        let vm = GifPickerViewModel(searcher: searcher, defaults: freshDefaults())
        try await type("cat", into: vm, searcher: searcher)
        vm.selectedIndex = 0
        vm.toggleProvider()
        let callsAfterFirstToggle = searcher.calls.count

        vm.toggleProvider()

        #expect(vm.provider == .giphy)
        #expect(searcher.calls.count == callsAfterFirstToggle)
        #expect(vm.results.map(\.id) == ["giphy-cat-0"])
    }

    @Test func toggleAfterQueryChangeSearchesAgain() async throws {
        let searcher = FakeSearcher()
        let vm = GifPickerViewModel(searcher: searcher, defaults: freshDefaults())
        try await type("cat", into: vm, searcher: searcher)
        vm.toggleProvider()                         // klipy: cat
        try await type("dog", into: vm, searcher: searcher)

        vm.toggleProvider()                         // giphy's cached "cat" is stale

        #expect(searcher.calls.last == .init(provider: .giphy, query: "dog", page: 0))
    }

    @Test func providerChoicePersists() {
        let defaults = freshDefaults()
        let vm = GifPickerViewModel(searcher: FakeSearcher(), defaults: defaults)
        vm.toggleProvider()
        let reopened = GifPickerViewModel(searcher: FakeSearcher(), defaults: defaults)
        #expect(reopened.provider == .klipy)
    }

    @Test func pagesAreCountedNotOffsetByResultCount() async throws {
        // A page that comes back short (an ad skipped, a malformed entry
        // dropped) must not shift the next request back onto the same page.
        final class ShortPageSearcher: GifSearching {
            var pages: [Int] = []
            func search(provider: GifProvider, query: String, pageSize: Int, page: Int,
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
        let vm = GifPickerViewModel(searcher: searcher, defaults: freshDefaults())
        vm.query = "cat"
        for _ in 0..<40 where searcher.pages.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        vm.loadMoreIfNeeded()
        #expect(searcher.pages == [0, 1])
    }
}
