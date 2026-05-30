import SwiftUI

/// The full-library grid, shown by *growing the picker panel* (not a separate
/// window). Driven by the trigger state machine through `EmojiBrowserViewModel`
/// — the panel stays non-key so the focused app keeps its insertion point and
/// picks are typed straight in.
struct InlineBrowserView: View {
    @ObservedObject var browser: EmojiBrowserViewModel
    let onPick: (Emoji) -> Void
    let onCategory: (EmojiCategory) -> Void

    @State private var activeCategory: String?
    @State private var hoverName: String?
    @State private var hoverWork: DispatchWorkItem?

    private static let space = "browserGrid"
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
                Text("Type to search emoji").foregroundStyle(.tertiary)
            } else {
                Text(browser.query).foregroundStyle(.primary)
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
                                sectionHeader(entry.section.category)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
            .coordinateSpace(name: Self.space)
            .onChange(of: browser.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(target, anchor: target.hasPrefix("cell-") ? nil : .top)
                }
            }
            .onPreferenceChange(HeaderOffsetKey.self) { positions in
                guard browser.query.isEmpty else { activeCategory = nil; return }
                // The pinned header sits at y≈0; pick the one closest to the
                // pin line from at/above it.
                let pinned = positions.filter { $0.value <= 4 }.max { $0.value < $1.value }
                activeCategory = pinned?.key ?? positions.min { $0.value < $1.value }?.key
            }
            .overlay(alignment: .bottom) { hoverReadout }
        }
    }

    @ViewBuilder
    private var hoverReadout: some View {
        if let hoverName {
            Text(hoverName)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.thickMaterial))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
                .padding(.bottom, 8)
                .allowsHitTesting(false)
                .transition(.opacity)
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
            .onTapGesture { onPick(emoji) }
            .onHover { hovering in
                hoverWork?.cancel()
                if hovering {
                    browser.selectedIndex = index
                    // Reveal the shortcode after a dwell so people can learn it.
                    let name = ":\(emoji.primaryShortcode):"
                    let work = DispatchWorkItem {
                        withAnimation(.easeOut(duration: 0.12)) { hoverName = name }
                    }
                    hoverWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                } else {
                    withAnimation(.easeOut(duration: 0.12)) { hoverName = nil }
                }
            }
    }

    private func sectionHeader(_ category: EmojiCategory) -> some View {
        Text(category.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            // Opaque enough that scrolling emoji don't tint the pinned header.
            .background(.thickMaterial)
            .id(category.id)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: HeaderOffsetKey.self,
                        value: [category.id: geo.frame(in: .named(Self.space)).minY]
                    )
                }
            )
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
                let isActive = activeCategory == category.id
                Button {
                    activeCategory = category.id
                    onCategory(category)
                } label: {
                    Image(systemName: category.tabSymbol)
                        .font(.system(size: 13))
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                        .frame(width: 30, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isActive ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(category.title)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.thickMaterial)
    }
}

/// Reports each section header's vertical offset in the grid's coordinate
/// space so the active category tab can light up as you scroll.
private struct HeaderOffsetKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

enum BrowserLayout {
    static let width: CGFloat = 352
    static let height: CGFloat = 420
    static let cornerRadius: CGFloat = 12
}
