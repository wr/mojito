import Combine
import Foundation

@MainActor
final class PickerViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [ScoredEmoji] = []
    @Published var selectedIndex: Int = 0
    @Published var isVisible: Bool = false
    /// True for the bare-`:` favorites surface, which renders as a compact
    /// horizontal pill instead of the vertical shortcode list.
    @Published var compact: Bool = false

    /// Mouse-pick from the picker (compact bar cells). The Engine sets this;
    /// the index is the cell tapped.
    var onActivate: ((Int) -> Void)?

    var topResult: ScoredEmoji? {
        guard !results.isEmpty, selectedIndex < results.count else { return nil }
        return results[selectedIndex]
    }

    func update(query: String, results: [ScoredEmoji]) {
        self.query = query
        self.results = results
        self.selectedIndex = min(selectedIndex, max(0, results.count - 1))
    }

    func selectNext() {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % results.count
    }

    func selectPrevious() {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + results.count) % results.count
    }

    func reset() {
        query = ""
        results = []
        selectedIndex = 0
        isVisible = false
        compact = false
    }
}
