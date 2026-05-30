import Combine
import Foundation

/// One labelled block in the browser grid.
struct BrowserSection: Identifiable {
    let category: EmojiCategory
    let emoji: [Emoji]
    var id: String { category.id }
}

/// Drives the in-panel emoji browser. Input arrives via the trigger state
/// machine (the panel is non-key, like the inline picker), so search + grid
/// navigation are set from the Engine rather than from focusable controls.
@MainActor
final class EmojiBrowserViewModel: ObservableObject {
    /// Fixed grid width — keep in sync with the LazyVGrid column count.
    static let columns = 9

    @Published private(set) var query: String = ""
    @Published private(set) var sections: [BrowserSection] = []
    @Published var selectedIndex: Int = 0
    /// Bumped to ask the view to scroll a category header into view.
    @Published var scrollTarget: String?

    private let database: EmojiDatabase
    private let usage: [String: Int]
    private let baseSections: [BrowserSection]

    init(database: EmojiDatabase, favorites: FavoritesStore) {
        self.database = database
        self.usage = (UserDefaults.standard.dictionary(forKey: PrefsKey.usageCounts) as? [String: Int]) ?? [:]
        self.baseSections = Self.buildSections(database: database, favorites: favorites, usage: self.usage)
        self.sections = baseSections
    }

    /// Flattened emoji across all sections, in display order — the space the
    /// selection index moves through.
    var flat: [Emoji] { sections.flatMap(\.emoji) }

    var selectedEmoji: Emoji? {
        let f = flat
        guard f.indices.contains(selectedIndex) else { return f.first }
        return f[selectedIndex]
    }

    var visibleCategories: [EmojiCategory] { baseSections.map(\.category) }

    func setQuery(_ newQuery: String) {
        query = newQuery
        recompute()
    }

    func move(_ direction: GifMoveDirection) {
        let count = flat.count
        guard count > 0 else { return }
        var next = selectedIndex
        switch direction {
        case .left:  next -= 1
        case .right: next += 1
        case .up:    next -= Self.columns
        case .down:  next += Self.columns
        }
        selectedIndex = min(max(next, 0), count - 1)
        // Keep the selected glyph in view.
        if let hex = selectedEmoji?.hexcode { scrollTarget = "cell-\(hex)" }
    }

    /// Mouse pick: snap the selection to the clicked glyph.
    func select(_ emoji: Emoji) {
        if let idx = flat.firstIndex(where: { $0.hexcode == emoji.hexcode }) {
            selectedIndex = idx
        }
    }

    func scroll(to category: EmojiCategory) {
        if !query.isEmpty { setQuery("") }
        scrollTarget = category.id
    }

    private func recompute() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            sections = baseSections
        } else {
            let hits = FuzzyMatcher.search(
                query: trimmed, in: database, usage: usage,
                corpus: .emojiOnly, useFrequencyBoost: true, limit: 240
            )
            .map(\.emoji)
            .filter { database.byHexcode[$0.hexcode] != nil }  // drop egg/sentinel rows
            sections = hits.isEmpty ? [] : [BrowserSection(category: .smileysPeople, emoji: hits)]
        }
        selectedIndex = 0
    }

    private static func buildSections(
        database: EmojiDatabase,
        favorites: FavoritesStore,
        usage: [String: Int]
    ) -> [BrowserSection] {
        var sections: [BrowserSection] = []

        let mostUsed = usage
            .filter { $0.value > 0 && !$0.key.hasPrefix("SYM_") }
            .sorted { $0.value > $1.value }
            .prefix(24)
            .compactMap { database.byHexcode[$0.key] }
        if !mostUsed.isEmpty {
            sections.append(BrowserSection(category: .frequentlyUsed, emoji: Array(mostUsed)))
        }

        let favEmoji = favorites.hexcodes.compactMap { database.byHexcode[$0] }
        if !favEmoji.isEmpty {
            sections.append(BrowserSection(category: .favorites, emoji: favEmoji))
        }

        for category in EmojiCategory.allCases where !category.isDynamic {
            let groups = Set(category.groups)
            let emoji = database.all.filter { groups.contains($0.group) }
            if !emoji.isEmpty {
                sections.append(BrowserSection(category: category, emoji: emoji))
            }
        }
        return sections
    }
}
