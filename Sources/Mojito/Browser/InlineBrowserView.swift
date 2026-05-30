import SwiftUI

/// The full-library grid, shown by *growing the picker panel* (not a separate
/// window). Driven by the trigger state machine through `EmojiBrowserViewModel`
/// — the panel stays non-key so the focused app keeps its insertion point and
/// picks are typed straight in.
struct InlineBrowserView: View {
    @ObservedObject var browser: EmojiBrowserViewModel
    let onPick: (Emoji) -> Void
    let onCategory: (EmojiCategory) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 32), spacing: 3),
        count: EmojiBrowserViewModel.columns
    )

    /// Sections paired with each glyph's flat selection index.
    private var indexedSections: [(section: BrowserSection, items: [(index: Int, emoji: Emoji)])] {
        var running = 0
        return browser.sections.map { section in
            let items = section.emoji.map { emoji -> (Int, Emoji) in
                defer { running += 1 }
                return (running, emoji)
            }
            return (section, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            hairline
            grid
            hairline
            categoryBar
        }
        .frame(width: BrowserLayout.width, height: BrowserLayout.height)
    }

    /// Soft separator that reads on glass, unlike a full-contrast Divider.
    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
    }

    private var searchHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            if browser.query.isEmpty {
                Text("Type to search emoji")
                    .foregroundStyle(.tertiary)
            } else {
                Text(browser.query)
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6, pinnedViews: [.sectionHeaders]) {
                    if browser.sections.isEmpty {
                        emptyResults
                    } else {
                        ForEach(indexedSections, id: \.section.id) { entry in
                            Section {
                                LazyVGrid(columns: columns, spacing: 3) {
                                    ForEach(entry.items, id: \.emoji.hexcode) { item in
                                        cell(item.emoji, index: item.index)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.bottom, 4)
                            } header: {
                                sectionHeader(entry.section.category.title)
                                    .id(entry.section.category.id)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
            .onChange(of: browser.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(target, anchor: target.hasPrefix("cell-") ? nil : .top)
                }
            }
        }
    }

    private func cell(_ emoji: Emoji, index: Int) -> some View {
        let isSelected = index == browser.selectedIndex
        let glyph = emoji.supportsSkinTone
            ? SkinTone.current.apply(to: emoji.character)
            : emoji.character
        return Text(glyph)
            .font(.system(size: 22))
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear)
            )
            .id("cell-\(emoji.hexcode)")
            .contentShape(Rectangle())
            .help(":\(emoji.primaryShortcode):")
            .onTapGesture { onPick(emoji) }
            .onHover { if $0 { browser.selectedIndex = index } }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            // Blur the content scrolling under the pinned header (glassy),
            // rather than the opaque white `.bar` band.
            .background(.ultraThinMaterial)
    }

    private var emptyResults: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("No emoji matching “\(browser.query)”")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    private var categoryBar: some View {
        HStack(spacing: 1) {
            ForEach(browser.visibleCategories) { category in
                Button {
                    onCategory(category)
                } label: {
                    Image(systemName: category.tabSymbol)
                        .font(.system(size: 13))
                        .frame(width: 30, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(category.title)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

enum BrowserLayout {
    static let width: CGFloat = 352
    static let height: CGFloat = 420
    static let cornerRadius: CGFloat = 12
}
