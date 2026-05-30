import Combine
import Foundation

/// Drives the in-panel emoji browser. Input arrives via the trigger state
/// machine (the panel is non-key, like the inline picker), so search + grid
/// navigation are set from the Engine rather than from focusable controls.
///
/// Navigation model: **one continuous scrolling list** (like the macOS system
/// emoji picker). Every category is a section in a single scroll view; the tab
/// bar *jumps* to a section and highlights whichever section you've scrolled to.
/// Cells carry a global flat index so keyboard nav + `scrollTo` address the
/// whole library with one integer, while section headers carry the category as
/// their scroll id.
@MainActor
final class EmojiBrowserViewModel: ObservableObject {
    /// Grid column count — keep in sync with the view's LazyVGrid.
    static let columns = 8

    /// A single emoji cell carrying its global flat index as its identity —
    /// the one id used for both `ForEach` and `scrollTo`. Avoiding a second
    /// (`.id()`) identity is what stops SwiftUI's lazy diff from keeping stale
    /// cells around and ghosting one section's glyphs over another's.
    struct Cell: Identifiable {
        let id: Int
        let emoji: Emoji
    }

    /// One category's worth of cells. `startIndex` is the global index of its
    /// first cell (used to park the keyboard selection on a tab jump).
    struct Section: Identifiable {
        let category: EmojiCategory
        let cells: [Cell]
        var id: EmojiCategory { category }
        var startIndex: Int { cells.first?.id ?? 0 }
    }

    @Published private(set) var query: String = ""
    /// Section currently at the top of the scroll view — drives the tab
    /// highlight. Derived from scroll position, not set by tab taps directly.
    @Published var activeCategory: EmojiCategory
    @Published var selectedIndex: Int = 0
    /// Flat cell index to scroll into view (keyboard nav / reset to top). The
    /// view clears it to nil after handling so the same index can repeat.
    @Published var scrollTarget: Int?
    /// Category section to jump to (tab tap). Cleared by the view after the
    /// jump so the same tab can be tapped twice.
    @Published var categoryTarget: EmojiCategory?

    private let database: EmojiDatabase
    private let usage: [String: Int]

    /// Sections in display order (only those with content).
    let sections: [Section]
    /// Every emoji, in section order — the flat list keyboard nav addresses.
    private let flat: [Emoji]

    var visibleCategories: [EmojiCategory] { sections.map(\.category) }

    init(database: EmojiDatabase, favorites: FavoritesStore) {
        self.database = database
        self.usage = (UserDefaults.standard.dictionary(forKey: PrefsKey.usageCounts) as? [String: Int]) ?? [:]
        let built = Self.build(database: database, favorites: favorites, usage: self.usage)
        self.sections = built
        self.flat = built.flatMap { $0.cells.map(\.emoji) }
        self.activeCategory = built.first?.category ?? .smileysPeople
    }

    /// The addressable list for selection + keyboard nav: search results when
    /// searching, else the whole library in section order.
    var current: [Emoji] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return flat }
        return FuzzyMatcher.search(
            query: trimmed, in: database, usage: usage,
            corpus: .emojiOnly, useFrequencyBoost: true, limit: 240
        )
        .map(\.emoji)
        .filter { database.byHexcode[$0.hexcode] != nil }  // drop egg/sentinel rows
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var selectedEmoji: Emoji? {
        let items = current
        guard items.indices.contains(selectedIndex) else { return items.first }
        return items[selectedIndex]
    }

    func setQuery(_ newQuery: String) {
        query = newQuery
        selectedIndex = 0
        scrollTarget = 0  // back to top on every query change
    }

    /// Tab tap: jump the scroll view to that category's section. Clears any
    /// search and parks the keyboard selection at the section's first cell.
    func selectCategory(_ category: EmojiCategory) {
        let wasSearching = isSearching
        query = ""
        if let section = sections.first(where: { $0.category == category }) {
            selectedIndex = section.startIndex
        }
        // If we were searching the list was a flat result grid; rebuilding the
        // sectioned list first, then jumping, keeps the target laid out.
        activeCategory = category
        categoryTarget = category
        if wasSearching { scrollTarget = nil }
    }

    func move(_ direction: GifMoveDirection) {
        let count = current.count
        guard count > 0 else { return }
        var next = selectedIndex
        switch direction {
        case .left:  next -= 1
        case .right: next += 1
        case .up:    next -= Self.columns
        case .down:  next += Self.columns
        }
        selectedIndex = min(max(next, 0), count - 1)
        scrollTarget = selectedIndex  // adjacent cell — scrollTo's safe case
    }

    /// Mouse pick: snap the selection to the clicked glyph.
    func select(_ emoji: Emoji) {
        if let idx = current.firstIndex(where: { $0.hexcode == emoji.hexcode }) {
            selectedIndex = idx
        }
    }

    /// Update the active tab from live section-header offsets (in the scroll
    /// view's coordinate space). The active section is the last header that has
    /// reached / passed the top edge. Headers below the fold (and ones recycled
    /// off the top) simply aren't in `offsets`; when none qualifies we keep the
    /// current tab rather than snapping to whatever header happens to be onscreen.
    func updateActiveCategory(from offsets: [EmojiCategory: CGFloat]) {
        guard !isSearching, !offsets.isEmpty else { return }
        let threshold: CGFloat = 1
        let atOrAboveTop = offsets.filter { $0.value <= threshold }
        guard let active = atOrAboveTop.max(by: { $0.value < $1.value })?.key else { return }
        if active != activeCategory { activeCategory = active }
    }

    private static func build(
        database: EmojiDatabase,
        favorites: FavoritesStore,
        usage: [String: Int]
    ) -> [Section] {
        var sections: [Section] = []
        var cursor = 0

        func add(_ category: EmojiCategory, _ emoji: [Emoji]) {
            guard !emoji.isEmpty else { return }
            let cells = emoji.enumerated().map { Cell(id: cursor + $0.offset, emoji: $0.element) }
            sections.append(Section(category: category, cells: cells))
            cursor += emoji.count
        }

        let mostUsed = usage
            .filter { $0.value > 0 && !$0.key.hasPrefix("SYM_") }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(24)
            .compactMap { database.byHexcode[$0.key] }
        add(.frequentlyUsed, Array(mostUsed))

        add(.favorites, favorites.hexcodes.compactMap { database.byHexcode[$0] })

        for category in EmojiCategory.allCases where !category.isDynamic {
            let groups = Set(category.groups)
            add(category, database.all.filter { groups.contains($0.group) })
        }

        // Typographic symbols (★ ⌘ ⌥ …) only when the Symbols feature is on —
        // the CoreText sweep is slow and the corpus is large.
        if UserDefaults.standard.bool(forKey: PrefsKey.symbolsEnabled) {
            add(.specialCharacters, SymbolsDatabase.indexed().map(\.emoji))
        }
        return sections
    }
}
