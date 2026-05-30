import SwiftUI

/// The full-library grid, shown by *growing the picker panel* (not a separate
/// window). Driven by the trigger state machine through `EmojiBrowserViewModel`
/// — the panel stays non-key so the focused app keeps its insertion point and
/// picks are typed straight in.
///
/// No section titles (Apple dropped them too) — groups are separated by space
/// and identified by the active tab + its tooltip.
struct InlineBrowserView: View {
    @ObservedObject var browser: EmojiBrowserViewModel
    let onPick: (Emoji) -> Void
    let onCategory: (EmojiCategory) -> Void

    @State private var activeCategory: String?

    private static let space = "browserGrid"
    private static let tabBarHeight: CGFloat = 38
    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 32), spacing: 3),
        count: EmojiBrowserViewModel.columns
    )
    private var barTint: Color { Color(nsColor: .windowBackgroundColor) }

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
            gridWithBar
        }
        .frame(width: BrowserLayout.width, height: BrowserLayout.height)
        .background(barTint)
    }

    private var hairline: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
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

    private var gridWithBar: some View {
        ZStack(alignment: .bottom) {
            grid
            // Floating frosted bar — the grid scrolls under it, blurred, with
            // a short gradient so glyphs dissolve into it.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [barTint.opacity(0), barTint.opacity(0.85)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 12)
                .allowsHitTesting(false)
                categoryBar
            }
        }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if browser.sections.isEmpty {
                        emptyResults
                    } else {
                        ForEach(indexedSections, id: \.section.id) { entry in
                            sectionAnchor(entry.section.category)
                            LazyVGrid(columns: columns, spacing: 3) {
                                ForEach(entry.items, id: \.emoji.hexcode) { item in
                                    cell(item.emoji, index: item.index)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 16)  // gap between groups
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, Self.tabBarHeight + 4)  // clear the floating bar
            }
            .coordinateSpace(name: Self.space)
            .onChange(of: browser.scrollTarget) { _, target in
                guard let target else { return }
                proxy.scrollTo(target, anchor: target.hasPrefix("cell-") ? nil : .top)
            }
            .onPreferenceChange(SectionOffsetKey.self) { positions in
                guard browser.query.isEmpty else { activeCategory = nil; return }
                let above = positions.filter { $0.value <= 12 }.max { $0.value < $1.value }
                activeCategory = above?.key ?? positions.min { $0.value < $1.value }?.key
            }
        }
    }

    /// Zero-height marker at the start of each group: the `scrollTo` target and
    /// the position probe for the active tab.
    private func sectionAnchor(_ category: EmojiCategory) -> some View {
        Color.clear
            .frame(height: 0)
            .id(category.id)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: SectionOffsetKey.self,
                        value: [category.id: geo.frame(in: .named(Self.space)).minY]
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
            .font(.system(size: 22))
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear)
            )
            .id("cell-\(emoji.hexcode)")
            .contentShape(Rectangle())
            .help(":\(emoji.primaryShortcode):")  // system tooltip
            .onTapGesture { onPick(emoji) }
            .onHover { if $0 { browser.selectedIndex = index } }
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
        .frame(height: Self.tabBarHeight)
        .background(.regularMaterial)
    }
}

/// Reports each group's vertical offset in the grid's coordinate space so the
/// active category tab can light up as you scroll.
private struct SectionOffsetKey: PreferenceKey {
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
