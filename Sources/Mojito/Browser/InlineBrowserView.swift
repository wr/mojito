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
    @State private var hoverHex: String?
    @State private var tooltipHex: String?
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
        // Opaque so scrolling glyphs never show through any part of the chrome.
        .background(Color(nsColor: .windowBackgroundColor))
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
                // Jump instantly — tab clicks shouldn't crawl.
                proxy.scrollTo(target, anchor: target.hasPrefix("cell-") ? nil : .top)
            }
            .onPreferenceChange(HeaderOffsetKey.self) { positions in
                guard browser.query.isEmpty else { activeCategory = nil; return }
                let pinned = positions.filter { $0.value <= 4 }.max { $0.value < $1.value }
                activeCategory = pinned?.key ?? positions.min { $0.value < $1.value }?.key
            }
            .overlayPreferenceValue(TooltipAnchorKey.self) { data in
                GeometryReader { proxy in
                    if let data {
                        let rect = proxy[data.anchor]
                        let nearTop = rect.minY < 30
                        tooltipBubble(data.text)
                            .fixedSize()
                            .position(
                                x: min(max(rect.midX, 46), proxy.size.width - 46),
                                y: nearTop ? rect.maxY + 16 : rect.minY - 13
                            )
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func tooltipBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.85)))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
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
            .anchorPreference(key: TooltipAnchorKey.self, value: .bounds) { anchor in
                tooltipHex == emoji.hexcode ? TooltipData(text: ":\(emoji.primaryShortcode):", anchor: anchor) : nil
            }
            .onTapGesture { onPick(emoji) }
            .onHover { hovering in
                hoverWork?.cancel()
                if hovering {
                    browser.selectedIndex = index
                    hoverHex = emoji.hexcode
                    let hex = emoji.hexcode
                    let work = DispatchWorkItem {
                        if hoverHex == hex {
                            withAnimation(.easeOut(duration: 0.1)) { tooltipHex = hex }
                        }
                    }
                    hoverWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                } else {
                    if hoverHex == emoji.hexcode { hoverHex = nil }
                    if tooltipHex == emoji.hexcode {
                        withAnimation(.easeOut(duration: 0.1)) { tooltipHex = nil }
                    }
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
            // Opaque so emoji scrolling under the pinned header don't tint it.
            .background(Color(nsColor: .windowBackgroundColor))
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
        .background(Color(nsColor: .windowBackgroundColor))
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

/// Carries the hovered cell's bounds + name to the tooltip overlay.
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

enum BrowserLayout {
    static let width: CGFloat = 352
    static let height: CGFloat = 420
    static let cornerRadius: CGFloat = 12
}
