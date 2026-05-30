import SwiftUI

/// Manage the favorites surfaced when the user types a bare `:`. Add by
/// searching, remove with one click. (Starring lives here, not in the
/// picker, by design.)
struct FavoritesSettingsView: View {
    @StateObject private var favorites = FavoritesStore.shared
    @AppStorage(PrefsKey.favoritesTrigger) private var triggerRaw: String = FavoritesTrigger.question.rawValue
    @State private var search: String = ""

    private let database = EmojiDatabase.shared
    private let addColumns = Array(repeating: GridItem(.flexible(minimum: 34), spacing: 4), count: 8)

    private var favoriteEmoji: [Emoji] {
        favorites.hexcodes.compactMap { database.byHexcode[$0] }
    }

    private var searchResults: [Emoji] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return FuzzyMatcher.search(
            query: trimmed, in: database, usage: [:],
            corpus: .emojiOnly, useFrequencyBoost: false, limit: 60
        )
        .map(\.emoji)
        // Drop egg/sentinel rows — only real, insertable emoji here.
        .filter { database.byHexcode[$0.hexcode] != nil }
    }

    var body: some View {
        Form {
            Section {
                Picker("Show favorites pill", selection: $triggerRaw) {
                    ForEach(FavoritesTrigger.allCases) { trigger in
                        Text(trigger.settingsLabel).tag(trigger.rawValue)
                    }
                }
                Text("Pops your favorites and most-used emoji. Return inserts the first; ←→ pick another; the ⌄ opens the full browser.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                if favoriteEmoji.isEmpty {
                    Text("No favorites yet — search below to add some.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(favoriteEmoji, id: \.hexcode) { emoji in
                        HStack(spacing: 10) {
                            Text(displayGlyph(emoji))
                                .font(.system(size: 20))
                            Text(":\(emoji.primaryShortcode):")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                favorites.remove(emoji.hexcode)
                            } label: {
                                Image(systemName: "star.slash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove from favorites")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Your favorites")
                    Spacer()
                    if !favoriteEmoji.isEmpty {
                        Button("Clear all") { favorites.clear() }
                            .buttonStyle(.borderless)
                            .font(.callout)
                    }
                }
            }

            Section("Add emoji") {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search emoji to add", text: $search)
                        .textFieldStyle(.plain)
                }
                if !search.isEmpty {
                    if searchResults.isEmpty {
                        Text("No matches.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: addColumns, spacing: 4) {
                            ForEach(searchResults, id: \.hexcode) { emoji in
                                addCell(emoji)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addCell(_ emoji: Emoji) -> some View {
        let isFav = favorites.isFavorite(emoji.hexcode)
        return Button {
            favorites.toggle(emoji.hexcode)
        } label: {
            Text(displayGlyph(emoji))
                .font(.system(size: 22))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isFav ? Color.accentColor.opacity(0.20) : .clear)
                )
                .overlay(alignment: .topTrailing) {
                    if isFav {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                            .padding(2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(isFav ? "Remove :\(emoji.primaryShortcode):" : "Add :\(emoji.primaryShortcode):")
    }

    private func displayGlyph(_ emoji: Emoji) -> String {
        emoji.supportsSkinTone ? SkinTone.current.apply(to: emoji.character) : emoji.character
    }
}
