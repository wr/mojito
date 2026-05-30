import Combine
import Foundation

/// Drives the in-panel emoji browser. Input arrives via the trigger state
/// machine (the panel is non-key, like the inline picker), so search + grid
/// navigation are set from the Engine rather than from focusable controls.
///
/// Navigation model: **one category at a time** (like the iOS emoji
/// keyboard). The tab bar *switches* which category is shown — it never
/// scrolls a long combined list. This removes the whole class of
/// `scrollTo`-to-an-offscreen-section bugs: a tab tap just swaps the dataset
/// and resets to the top. The only scrolling left is within the current
/// category (short) and incremental keyboard nav — `scrollTo`'s reliable case.
@MainActor
final class EmojiBrowserViewModel: ObservableObject {
    /// Grid column count — keep in sync with the view's LazyVGrid.
    static let columns = 8

    @Published private(set) var query: String = ""
    @Published var selectedCategory: EmojiCategory
    @Published var selectedIndex: Int = 0
    /// Cell index to scroll into view; the view clears it to nil after
    /// handling so the same index can be requested again.
    @Published var scrollTarget: Int?

    private let database: EmojiDatabase
    private let usage: [String: Int]
    /// Emoji per category, prebuilt once at open.
    private let byCategory: [EmojiCategory: [Emoji]]
    /// Visible categories in tab order (only those with content).
    let visibleCategories: [EmojiCategory]

    init(database: EmojiDatabase, favorites: FavoritesStore) {
        self.database = database
        self.usage = (UserDefaults.standard.dictionary(forKey: PrefsKey.usageCounts) as? [String: Int]) ?? [:]
        let (map, order) = Self.build(database: database, favorites: favorites, usage: self.usage)
        self.byCategory = map
        self.visibleCategories = order
        self.selectedCategory = order.first ?? .smileysPeople
    }

    /// The emoji currently shown: search results when searching, else the
    /// selected category's set.
    var current: [Emoji] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return byCategory[selectedCategory] ?? [] }
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

    /// Switch the shown category (tab tap). Clears any search and resets
    /// to the top — no long-list scroll, so nothing can drift.
    func selectCategory(_ category: EmojiCategory) {
        query = ""
        selectedCategory = category
        selectedIndex = 0
        scrollTarget = 0
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

    private static func build(
        database: EmojiDatabase,
        favorites: FavoritesStore,
        usage: [String: Int]
    ) -> (map: [EmojiCategory: [Emoji]], order: [EmojiCategory]) {
        var map: [EmojiCategory: [Emoji]] = [:]
        var order: [EmojiCategory] = []

        func add(_ category: EmojiCategory, _ emoji: [Emoji]) {
            guard !emoji.isEmpty else { return }
            map[category] = emoji
            order.append(category)
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
        return (map, order)
    }
}
