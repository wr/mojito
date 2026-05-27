import Combine
import Foundation

@MainActor
final class GifPickerViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [GifAsset] = []
    @Published var selectedIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isVisible: Bool = false

    /// 3-column grid; arrow keys + Enter handle navigation.
    let columns: Int = 3

    private let searcher = GifSearcher()
    private var queryCancellable: AnyCancellable?

    init() {
        // 250ms debounce — long enough to skip mid-word noise, short enough
        // that finished queries feel instant.
        queryCancellable = $query
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] q in self?.runSearch(q) }
    }

    func reset() {
        query = ""
        results = []
        selectedIndex = 0
        isLoading = false
        errorMessage = nil
    }

    func selectedAsset() -> GifAsset? {
        guard results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }

    /// Arrow-key navigation across a `columns`-wide grid.
    func moveSelection(_ direction: Direction) {
        guard !results.isEmpty else { return }
        let count = results.count
        let cols = columns
        switch direction {
        case .left:
            selectedIndex = max(0, selectedIndex - 1)
        case .right:
            selectedIndex = min(count - 1, selectedIndex + 1)
        case .up:
            selectedIndex = max(0, selectedIndex - cols)
        case .down:
            selectedIndex = min(count - 1, selectedIndex + cols)
        }
    }

    enum Direction { case left, right, up, down }

    private func runSearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isLoading = false
            errorMessage = nil
            selectedIndex = 0
            return
        }
        isLoading = true
        errorMessage = nil
        searcher.search(query: trimmed) { [weak self] result in
            guard let self else { return }
            self.isLoading = false
            switch result {
            case .success(let assets):
                self.results = assets
                self.selectedIndex = 0
                if assets.isEmpty {
                    self.errorMessage = String(localized: "No GIFs found.")
                }
            case .failure(let error):
                self.results = []
                self.errorMessage = error.userMessage
            }
        }
    }
}
