import Combine
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
    /// In the live panel the search row is display-only (the event tap feeds it).
    /// Hosted in a key window (the Settings slot picker), it becomes a real
    /// editable `TextField`.
    var editableSearch: Bool = false

    @State private var tooltipSize: CGSize = .zero
    @State private var typedQuery = ""
    @FocusState private var searchFieldFocused: Bool
    /// The caret only blinks once the search row is clicked (or text exists),
    /// so it doesn't imply a focusable field before then.
    @State private var searchClicked = false

    private static let scrollSpace = "browserScroll"
    private static let cellHeight: CGFloat = 40
    private static let rowSpacing: CGFloat = 3
    /// Tab bar height (icon row). The grid scrolls under it, so the scroll
    /// content is inset by this much at the bottom.
    private static let tabBarHeight: CGFloat = 38
    /// Soft fade zone above the icons where the glass ramps in from clear.
    private static let tabBarFade: CGFloat = 26
    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 36), spacing: 3),
        count: EmojiBrowserViewModel.columns
    )

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            hairline
            grid
        }
        .frame(width: BrowserLayout.width, height: BrowserLayout.height)
        // Tooltip drawn at the root so it can sit above the top row without
        // being clipped by the scroll view. Clamps to the panel using the
        // bubble's measured width and flips below near the search row, so long
        // shortcodes never overflow an edge.
        .overlayPreferenceValue(TooltipAnchorKey.self) { data in
            GeometryReader { proxy in
                if let data {
                    let cell = proxy[data.anchor]
                    let margin: CGFloat = 6
                    let halfW = tooltipSize.width / 2
                    let x = min(max(cell.midX, halfW + margin), proxy.size.width - halfW - margin)
                    let fitsAbove = cell.minY - margin - tooltipSize.height >= 40
                    let y = fitsAbove
                        ? cell.minY - margin - tooltipSize.height / 2
                        : cell.maxY + margin + tooltipSize.height / 2
                    EmojiTooltip(name: data.text)
                        .background(GeometryReader { g in
                            Color.clear
                                .onAppear { tooltipSize = g.size }
                                .onChange(of: g.size) { _, s in tooltipSize = s }
                        })
                        .position(x: x, y: y)
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
            if editableSearch {
                TextField("Search emoji", text: $typedQuery)
                    .textFieldStyle(.plain)
                    .focused($searchFieldFocused)
                    .onChange(of: typedQuery) { _, value in browser.setQuery(value) }
            } else {
                Text(browser.query).foregroundStyle(.primary)
                caret  // fixed slot — shows on click, never shifts the placeholder
                if browser.query.isEmpty {
                    Text(String(localized: "Type to search emoji")).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .frame(height: 36)
        .contentShape(Rectangle())
        .onTapGesture {
            searchClicked = true
            if editableSearch { searchFieldFocused = true }
        }
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
    /// per section is what let one section's glyphs ghost over another's. The
    /// tab bar is a bottom `safeAreaInset`: content scrolls *under* it (so emoji
    /// blur through the glass) while `scrollTo` keeps keyboard-selected cells
    /// above it instead of leaving them hidden behind it.
    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if browser.isSearching && browser.current.isEmpty {
                    emptyResults
                } else {
                    LazyVGrid(columns: columns, spacing: Self.rowSpacing) {
                        if browser.isSearching {
                            // Key by hexcode, not the positional offset: the
                            // sectioned branch identifies cells by a 0-based
                            // integer index, and a search list keyed by 0-based
                            // offsets collides with it — SwiftUI then reuses the
                            // library cells (the most-used row) for the first
                            // search render instead of rebuilding with the
                            // result glyphs. A hexcode id keeps the two identity
                            // spaces disjoint so the transition always refreshes.
                            ForEach(Array(browser.current.enumerated()), id: \.element.hexcode) { index, emoji in
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
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { categoryBar }
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
        BrowserCell(
            emoji: emoji,
            index: index,
            isKeyboardSelected: index == browser.selectedIndex,
            cellHeight: Self.cellHeight,
            onPick: onPick,
            onHoverChanged: { browser.hoverIndex = $0 }
        )
    }

    private var emptyResults: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(String(localized: "No emoji matching “\(browser.query)”"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    // MARK: Tab bar

    private var categoryBar: some View {
        ZStack(alignment: .bottom) {
            tabBarBackdrop
            CategoryTabBar(
                categories: browser.visibleCategories,
                isSearching: browser.isSearching,
                activeCategoryPublisher: browser.activeCategoryPublisher,
                initialActiveCategory: browser.activeCategory,
                tabBarHeight: Self.tabBarHeight,
                onCategory: onCategory
            )
        }
        .frame(height: Self.tabBarHeight + Self.tabBarFade)
    }

    /// Glass/material masked by a vertical gradient so it fades *in* toward the
    /// bottom — no hard top edge. Emoji scrolling under it blur and dim away as
    /// they approach the icons, matching the native picker's bottom bar.
    private var tabBarBackdrop: some View {
        Rectangle().fill(.clear)
            .modifier(TabBarGlass())
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.55),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

/// One emoji cell, broken out so hover state is per-cell `@State` and a cell
/// scrolling under the cursor only invalidates itself — not the parent
/// `InlineBrowserView`, which would re-evaluate the `ScrollView` and reset the
/// scroll position on macOS 27 beta 1.
private struct BrowserCell: View {
    let emoji: Emoji
    let index: Int
    let isKeyboardSelected: Bool
    let cellHeight: CGFloat
    let onPick: (Emoji) -> Void
    let onHoverChanged: (Int?) -> Void

    @State private var hovered: Bool = false
    @State private var showTooltip: Bool = false
    @State private var tooltipWork: DispatchWorkItem?

    var body: some View {
        let glyph = emoji.tonedGlyph
        let highlighted = isKeyboardSelected || hovered
        Text(glyph)
            .font(.system(size: 25))  // match the pill's glyph size
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(highlighted ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear)
            )
            .contentShape(Rectangle())
            .accessibilityLabel(Text(verbatim: emoji.label))
            .anchorPreference(key: TooltipAnchorKey.self, value: .bounds) { anchor in
                showTooltip ? TooltipData(text: ":\(emoji.primaryShortcode):", anchor: anchor) : nil
            }
            .onTapGesture { onPick(emoji) }
            .onHover { hovering in
                tooltipWork?.cancel()
                hovered = hovering
                onHoverChanged(hovering ? index : nil)
                if hovering {
                    let work = DispatchWorkItem { showTooltip = true }
                    tooltipWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                } else {
                    showTooltip = false
                }
            }
    }
}

/// Tab bar pulled into its own view so the active-section highlight tracks the
/// scroll position through a local `@State` driven by a Combine publisher,
/// instead of through a `@Published` on `EmojiBrowserViewModel`. The point: a
/// scroll-driven activeCategory change must not invalidate the parent
/// `InlineBrowserView` body (and re-evaluate the `ScrollView`/`LazyVGrid`
/// mid-scroll, which on macOS 27 beta 1 snapped the scroll position back).
private struct CategoryTabBar: View {
    let categories: [EmojiCategory]
    let isSearching: Bool
    let activeCategoryPublisher: AnyPublisher<EmojiCategory, Never>
    let tabBarHeight: CGFloat
    let onCategory: (EmojiCategory) -> Void
    @State private var activeCategory: EmojiCategory

    init(
        categories: [EmojiCategory],
        isSearching: Bool,
        activeCategoryPublisher: AnyPublisher<EmojiCategory, Never>,
        initialActiveCategory: EmojiCategory,
        tabBarHeight: CGFloat,
        onCategory: @escaping (EmojiCategory) -> Void
    ) {
        self.categories = categories
        self.isSearching = isSearching
        self.activeCategoryPublisher = activeCategoryPublisher
        self.tabBarHeight = tabBarHeight
        self.onCategory = onCategory
        self._activeCategory = State(initialValue: initialActiveCategory)
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(categories) { category in
                let isActive = !isSearching && activeCategory == category
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
        .frame(height: tabBarHeight)
        .onReceive(activeCategoryPublisher) { activeCategory = $0 }
    }
}

/// Liquid-glass backdrop for the floating tab bar (Tahoe `glassEffect`),
/// falling back to a translucent material pre-26 so emoji still show through.
private struct TabBarGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect)
        } else {
            content.background(.ultraThinMaterial)
        }
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
