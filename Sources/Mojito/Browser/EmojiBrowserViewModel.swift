import Combine
import Foundation

/// One labelled block in the browser grid.
struct BrowserSection: Identifiable {
    let category: EmojiCategory
    let emoji: [Emoji]
    var id: String { category.id }
}

@MainActor
final class EmojiBrowserViewModel: ObservableObject {
    @Published var query: String = ""
    /// Bumped to ask the view to scroll a category header into view.
    @Published var scrollTarget: String?

    private let database: EmojiDatabase
    private let favorites: FavoritesStore
    private let usage: [String: Int]

    /// Static-ish sections built once at open (favorites + most-used are
    /// snapshotted; the window is short-lived so we don't live-refresh them).
    let baseSections: [BrowserSection]

    init(database: EmojiDatabase, favorites: FavoritesStore) {
        self.database = database
        self.favorites = favorites
        self.usage = (UserDefaults.standard.dictionary(forKey: PrefsKey.usageCounts) as? [String: Int]) ?? [:]
        self.baseSections = Self.buildSections(
            database: database,
            favorites: favorites,
            usage: self.usage
        )
    }

    /// Tabs to show in the bottom bar — only categories that actually have
    /// rows (so an empty Favorites / Frequently Used tab doesn't show).
    var visibleCategories: [EmojiCategory] {
        baseSections.map(\.category)
    }

    /// Sections to render: the category blocks when idle, a single flat
    /// "Results" block when searching.
    var displaySections: [BrowserSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return baseSections }
        let hits = FuzzyMatcher.search(
            query: trimmed,
            in: database,
            usage: usage,
            corpus: .emojiOnly,
            useFrequencyBoost: true,
            limit: 240
        )
        // Drop egg/sentinel rows — the browser is a plain library view.
        let emoji = hits
            .map(\.emoji)
            .filter { database.byHexcode[$0.hexcode] != nil }
        guard !emoji.isEmpty else { return [] }
        return [BrowserSection(category: .smileysPeople, emoji: emoji)]
    }

    /// First match while searching — Return in the search field inserts it.
    var topResult: Emoji? {
        displaySections.first?.emoji.first
    }

    func scroll(to category: EmojiCategory) {
        query = ""
        scrollTarget = category.id
    }

    private static func buildSections(
        database: EmojiDatabase,
        favorites: FavoritesStore,
        usage: [String: Int]
    ) -> [BrowserSection] {
        var sections: [BrowserSection] = []

        // Frequently used (snapshot, top 24).
        let mostUsed = usage
            .filter { $0.value > 0 && !$0.key.hasPrefix("SYM_") }
            .sorted { $0.value > $1.value }
            .prefix(24)
            .compactMap { database.byHexcode[$0.key] }
        if !mostUsed.isEmpty {
            sections.append(BrowserSection(category: .frequentlyUsed, emoji: Array(mostUsed)))
        }

        // Favorites (user order).
        let favEmoji = favorites.hexcodes.compactMap { database.byHexcode[$0] }
        if !favEmoji.isEmpty {
            sections.append(BrowserSection(category: .favorites, emoji: favEmoji))
        }

        // Group-backed categories, in catalog order.
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
