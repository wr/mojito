import Testing
@testable import Mojito

/// Selection bookkeeping in `PickerViewModel.update`. A new query snaps the
/// highlight back to the top hit (the list scrolls to top alongside it); a
/// same-query refresh keeps the user's position, clamped to the new count.
@MainActor
struct PickerViewModelTests {

    private func rows(_ n: Int) -> [ScoredEmoji] {
        let emoji = Emoji(hexcode: "1F600", character: "😀", label: "grinning",
                          shortcodes: ["grinning"], tags: [], group: 0, order: 1)
        return (0..<n).map { _ in ScoredEmoji(emoji: emoji, matchedShortcode: "grinning") }
    }

    @Test func newQueryResetsSelectionToTop() {
        let vm = PickerViewModel()
        vm.update(query: "thumbs", results: rows(5))
        vm.selectedIndex = 3
        vm.update(query: "heart", results: rows(5))
        #expect(vm.selectedIndex == 0)
    }

    @Test func sameQueryRefreshKeepsClampedSelection() {
        let vm = PickerViewModel()
        vm.update(query: "cat", results: rows(6))
        vm.selectedIndex = 4
        vm.update(query: "cat", results: rows(3))
        #expect(vm.selectedIndex == 2)
    }
}
