import Combine
import Foundation

@MainActor
final class GifPickerViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [GifAsset] = []
    @Published var selectedIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    /// True when the last search died on a request failure (vs. an empty
    /// result set) — gates the "Try Again" affordance.
    @Published var lastSearchFailed: Bool = false
    @Published var isVisible: Bool = false

    /// 3-column grid; arrow keys + Enter handle navigation.
    let columns: Int = 3
    /// Giphy's max per-page is 50; 24 is roughly the screen-fill threshold
    /// for the 3-col grid, so paging-in-3-rows feels natural.
    private let pageSize: Int = 24
    /// Auto-pagination stops at this many results. Past the cap, the
    /// grid surfaces a "Load more" button so further pages are explicit
    /// user opt-in — keeps API usage in check for idle drag-the-scrollbar.
    let autoPaginateCap: Int = 60

    /// Surfaces the "Load more" button when an auto-load was suppressed
    /// because we hit `autoPaginateCap` (and Giphy has more to give).
    @Published var canLoadMore: Bool = false

    private let searcher = GifSearcher()
    private var queryCancellable: AnyCancellable?

    /// Current trimmed query the result set belongs to. Used to detect
    /// stale loadMore completions after the user keeps typing.
    private var lastQuery: String = ""
    private var pageOffset: Int = 0
    /// False once Giphy returned an under-full page — stops further fetches.
    private var hasMore: Bool = false
    private var isPaginating: Bool = false

    init() {
        // 300ms debounce — within the 250–400ms window most search-as-you-
        // type UIs target. Waits for the user to actually pause before
        // burning an API call, while still feeling responsive on settle.
        queryCancellable = $query
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] q in self?.runSearch(q) }
    }

    func reset() {
        query = ""
        results = []
        selectedIndex = 0
        isLoading = false
        errorMessage = nil
        lastSearchFailed = false
        lastQuery = ""
        pageOffset = 0
        hasMore = false
        canLoadMore = false
        isPaginating = false
    }

    func selectedAsset() -> GifAsset? {
        guard results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }

    /// True when the "Load more" pseudo-row owns the keyboard focus —
    /// selectedIndex sits one slot past the last GIF.
    var isLoadMoreFocused: Bool {
        canLoadMore && selectedIndex == results.count
    }

    /// Arrow-key navigation across a `columns`-wide grid. When
    /// `canLoadMore` is true, index `results.count` is a virtual extra
    /// slot representing the "Load more" button.
    func moveSelection(_ direction: Direction) {
        guard !results.isEmpty else { return }
        let count = results.count
        let cols = columns
        let maxIndex = canLoadMore ? count : count - 1
        switch direction {
        case .left:
            selectedIndex = max(0, selectedIndex - 1)
        case .right:
            selectedIndex = min(maxIndex, selectedIndex + 1)
        case .up:
            selectedIndex = max(0, selectedIndex - cols)
        case .down:
            selectedIndex = min(maxIndex, selectedIndex + cols)
        }
    }

    enum Direction { case left, right, up, down }

    /// Called by the grid's onAppear-on-tail-cells. No-op past the
    /// `autoPaginateCap` — the user has to click "Load more" past that
    /// point (see `loadMore()`).
    func loadMoreIfNeeded() {
        guard results.count < autoPaginateCap else {
            canLoadMore = hasMore && !isPaginating
            return
        }
        fetchNextPage()
    }

    /// Explicit "Load more" — fires past the auto-pagination cap.
    func loadMore() {
        fetchNextPage()
    }

    /// Re-runs the search that just failed (the "Try Again" button).
    func retrySearch() {
        let q = lastQuery.isEmpty
            ? query.trimmingCharacters(in: .whitespacesAndNewlines)
            : lastQuery
        guard !q.isEmpty else { return }
        runSearch(q)
    }

    private func fetchNextPage() {
        guard hasMore, !isPaginating, !lastQuery.isEmpty else { return }
        isPaginating = true
        // Keep `canLoadMore` true while the fetch is in flight — hiding
        // the button would shift the ScrollView content out from under
        // the user. The button's own `disabled` state covers double-tap.
        let queryAtDispatch = lastQuery
        let offsetAtDispatch = pageOffset
        searcher.search(query: queryAtDispatch, limit: pageSize, offset: offsetAtDispatch) { [weak self] result in
            guard let self else { return }
            self.isPaginating = false
            // User retyped while the page was in flight — drop the stale
            // append rather than splicing it onto a different result set.
            guard self.lastQuery == queryAtDispatch else { return }
            switch result {
            case .success(let assets):
                let oldCount = self.results.count
                self.results.append(contentsOf: assets)
                self.pageOffset += assets.count
                self.hasMore = assets.count >= self.pageSize
                // If selection sat on the Load-more pseudo-row, snap it
                // forward to the first new GIF so navigation continues
                // naturally instead of pointing at empty space.
                if self.selectedIndex >= oldCount, !assets.isEmpty {
                    self.selectedIndex = oldCount
                }
            case .failure:
                self.hasMore = false
            }
            // Re-evaluate the cap: if we're now at/past it AND Giphy still
            // has more, surface the explicit-load button.
            self.canLoadMore = self.hasMore && self.results.count >= self.autoPaginateCap
        }
    }

    private func runSearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isLoading = false
            errorMessage = nil
            lastSearchFailed = false
            selectedIndex = 0
            lastQuery = ""
            pageOffset = 0
            hasMore = false
            return
        }
        // Did the user's actual search change, or are we just refiring on
        // an incidental edit (trailing space, etc.)? Fresh searches clear
        // the previous results immediately so the next page doesn't paint
        // below stale ones; trim-equal refires leave results intact.
        let queryChanged = (trimmed != lastQuery)
        isLoading = true
        errorMessage = nil
        lastSearchFailed = false
        lastQuery = trimmed
        pageOffset = 0
        hasMore = true
        // `GifSearcher` cancels any in-flight task, including a pagination
        // request mid-flight. Cancelled tasks don't fire their completion,
        // so we'd never see `isPaginating` reset back to false — clear it
        // here so the Load-more affordance isn't stuck disabled forever.
        isPaginating = false
        if queryChanged {
            results = []
            selectedIndex = 0
            canLoadMore = false
        }
        searcher.search(query: trimmed, limit: pageSize, offset: 0) { [weak self] result in
            guard let self else { return }
            self.isLoading = false
            // The user kept typing while this request was inflight — its
            // cancellation was racy; drop the result.
            guard self.lastQuery == trimmed else { return }
            switch result {
            case .success(let assets):
                self.results = assets
                self.pageOffset = assets.count
                self.hasMore = assets.count >= self.pageSize
                if assets.isEmpty {
                    self.errorMessage = String(localized: "No GIFs found.")
                }
            case .failure(let error):
                self.results = []
                self.errorMessage = error.userMessage
                self.lastSearchFailed = true
                self.hasMore = false
            }
        }
    }
}
