import Combine
import Foundation

@MainActor
final class PickerViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [ScoredEmoji] = []
    @Published var selectedIndex: Int = 0
    @Published var isVisible: Bool = false
    /// True for the `:?` (empty-query) favorites surface, which renders as a
    /// compact horizontal pill instead of the vertical shortcode list.
    @Published var compact: Bool = false
    /// True once the pill has grown into the full-library grid (same panel).
    @Published var expanded: Bool = false

    /// Drives the grid while `expanded`. Set by the Engine on expand.
    var browser: EmojiBrowserViewModel?

    /// Mouse-pick from the picker (compact bar cells). The Engine sets this;
    /// the index is the cell tapped.
    var onActivate: ((Int) -> Void)?
    /// Mouse-pick on a vertical-list row (the typed-query shortcode list). The
    /// Engine sets this; the index is the row clicked.
    var onPickRow: ((Int) -> Void)?
    /// Hover over a pill cell (nil = hover ended). PickerWindow shows the
    /// number-hotkey tooltip above that cell. The pill panel is too short to
    /// host the tooltip itself, so it lives in a separate panel.
    var onPillHover: ((Int?) -> Void)?
    /// Mouse-pick / tab-click inside the expanded grid.
    var onBrowserPick: ((Emoji) -> Void)?
    var onBrowserCategory: ((EmojiCategory) -> Void)?

    var topResult: ScoredEmoji? {
        guard !results.isEmpty, selectedIndex < results.count else { return nil }
        return results[selectedIndex]
    }

    func update(query: String, results: [ScoredEmoji]) {
        // A new query invalidates the old highlight — snap to the top hit
        // (the list also scrolls to top). Same-query refreshes keep the
        // (clamped) position.
        if query != self.query {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex, max(0, results.count - 1))
        }
        self.query = query
        self.results = results
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
        expanded = false
        browser = nil
    }
}
