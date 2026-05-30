import SwiftUI

/// The full-library grid, shown by *growing the picker panel* (not a separate
/// window). Driven by the trigger state machine through `EmojiBrowserViewModel`
/// — the panel stays non-key so the focused app keeps its insertion point and
/// picks are typed straight in.
///
/// One **continuous scrolling list** (like the macOS system emoji picker): every
/// category is a section in a single scroll view. The tab bar jumps to a section
/// and tracks whichever section you've scrolled to. The outer container is a
/// plain `VStack` (not lazy) so each section sits at an exact offset — that's
/// what makes `scrollTo` pixel-accurate with no drift — while each section's
/// `LazyVGrid` still renders its cells lazily, so opening stays cheap.
///
/// The panel is non-key, so native `.help` tooltips don't fire; glyph names use
/// a custom root overlay.
struct InlineBrowserView: View {
    @ObservedObject var browser: EmojiBrowserViewModel
    let onPick: (Emoji) -> Void
    let onCategory: (EmojiCategory) -> Void

    @State private var hoverIndex: Int?
    @State private var tooltipIndex: Int?
    @State private var hoverWork: DispatchWorkItem?
    /// The caret only blinks once the search row is clicked (or text exists),
    /// so it doesn't imply a focusable field before then.
    @State private var searchClicked = false

    private static let scrollSpace = "browserScroll"
    private static let cellHeight: CGFloat = 40
    private static let rowSpacing: CGFloat = 3
    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 36), spacing: 3),
        count: EmojiBrowserViewModel.columns
    )

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            hairline
            grid
            hairline
            categoryBar
        }
        .frame(width: BrowserLayout.width, height: BrowserLayout.height)
        // Tooltip drawn at the root so it can sit above the top row without
        // being clipped by the scroll view.
        .overlayPreferenceValue(TooltipAnchorKey.self) { data in
            GeometryReader { proxy in
                if let data {
                    let rect = proxy[data.anchor]
                    tooltipBubble(data.text)
                        .position(
                            x: min(max(rect.midX, 44), proxy.size.width - 44),
                            y: max(rect.minY - 15, 16)
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var hairline: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
    }

    // MARK: Search row

    private var searchHeader: some View {
        HStack(spacing: 3) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .padding(.trailing, 3)
            Text(browser.query).foregroundStyle(.primary)
            caret  // fixed slot — shows on click, never shifts the placeholder
            if browser.query.isEmpty {
                Text("Type to search emoji").foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .frame(height: 36)
        .contentShape(Rectangle())
        .onTapGesture { searchClicked = true }
    }

    private var caret: some View {
        let visible = searchClicked || !browser.query.isEmpty
        return TimelineView(.periodic(from: .now, by: 0.6)) { context in
            let on = Int(context.date.timeIntervalSince1970 / 0.6) % 2 == 0
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 2, height: 17)
                .opacity(visible && on ? 1 : 0)
        }
        .frame(width: 2)
    }

    // MARK: Grid (continuous list / search results)

    /// One `LazyVGrid` for the whole library (sectioned) or the flat search
    /// results. A single lazy container recycles cells correctly — splitting it
    /// per section is what let one section's glyphs ghost over another's.
    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if browser.isSearching && browser.current.isEmpty {
                    emptyResults
                } else {
                    LazyVGrid(columns: columns, spacing: Self.rowSpacing) {
                        if browser.isSearching {
                            ForEach(Array(browser.current.enumerated()), id: \.offset) { index, emoji in
                                cell(emoji, index: index)
                            }
                        } else {
                            ForEach(browser.sections) { section in
                                Section {
                                    ForEach(section.cells) { item in
                                        cell(item.emoji, index: item.id)
                                    }
                                } header: {
                                    sectionHeader(section.category)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
            .coordinateSpace(name: Self.scrollSpace)
            // Active tab follows the scroll position.
            .onPreferenceChange(SectionOffsetKey.self) { offsets in
                browser.updateActiveCategory(from: offsets)
            }
            // Keyboard nav / reset-to-top scroll a single cell into view.
            .onChange(of: browser.scrollTarget) { _, target in
                guard let target else { return }
                proxy.scrollTo(target, anchor: target == 0 ? .top : nil)
                DispatchQueue.main.async { browser.scrollTarget = nil }
            }
            // Tab tap jumps to a section header.
            .onChange(of: browser.categoryTarget) { _, target in
                guard let target else { return }
                proxy.scrollTo(target, anchor: .top)
                DispatchQueue.main.async { browser.categoryTarget = nil }
            }
        }
    }

    private func sectionHeader(_ category: EmojiCategory) -> some View {
        Text(category.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .id(category)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: SectionOffsetKey.self,
                        value: [category: geo.frame(in: .named(Self.scrollSpace)).minY]
                    )
                }
            )
    }

    private func cell(_ emoji: Emoji, index: Int) -> some View {
        let isSelected = index == browser.selectedIndex
        let glyph = emoji.supportsSkinTone
            ? SkinTone.current.apply(to: emoji.character)
            : emoji.character
        return Text(glyph)
            .font(.system(size: 25))  // match the pill's glyph size
            .frame(maxWidth: .infinity)
            .frame(height: Self.cellHeight)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear)
            )
            .contentShape(Rectangle())
            .anchorPreference(key: TooltipAnchorKey.self, value: .bounds) { anchor in
                tooltipIndex == index ? TooltipData(text: ":\(emoji.primaryShortcode):", anchor: anchor) : nil
            }
            .onTapGesture { onPick(emoji) }
            .onHover { hovering in
                hoverWork?.cancel()
                if hovering {
                    browser.selectedIndex = index
                    hoverIndex = index
                    let work = DispatchWorkItem {
                        if hoverIndex == index { tooltipIndex = index }
                    }
                    hoverWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                } else {
                    if hoverIndex == index { hoverIndex = nil }
                    if tooltipIndex == index { tooltipIndex = nil }
                }
            }
    }

    private func tooltipBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15))
            )
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
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

    // MARK: Tab bar

    private var categoryBar: some View {
        HStack(spacing: 1) {
            ForEach(browser.visibleCategories) { category in
                // Active = the section scrolled to the top (cleared while searching).
                let isActive = !browser.isSearching && browser.activeCategory == category
                Button {
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
        .padding(.vertical, 6)
        .background(.regularMaterial)
    }
}

/// Carries the hovered cell's bounds + name to the root tooltip overlay.
private struct TooltipData {
    let text: String
    let anchor: Anchor<CGRect>
}

private struct TooltipAnchorKey: PreferenceKey {
    static var defaultValue: TooltipData? = nil
    static func reduce(value: inout TooltipData?, nextValue: () -> TooltipData?) {
        value = nextValue() ?? value
    }
}

/// Each section header reports its top offset (in the scroll view's coordinate
/// space) so the view model can tell which section is currently at the top.
private struct SectionOffsetKey: PreferenceKey {
    static var defaultValue: [EmojiCategory: CGFloat] = [:]
    static func reduce(value: inout [EmojiCategory: CGFloat], nextValue: () -> [EmojiCategory: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

enum BrowserLayout {
    static let width: CGFloat = 352
    static let height: CGFloat = 420
    static let cornerRadius: CGFloat = 12
}
