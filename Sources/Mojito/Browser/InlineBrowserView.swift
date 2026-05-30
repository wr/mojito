import SwiftUI

/// The full-library grid, shown by *growing the picker panel* (not a separate
/// window). Driven by the trigger state machine through `EmojiBrowserViewModel`
/// — the panel stays non-key so the focused app keeps its insertion point and
/// picks are typed straight in.
///
/// No section titles (Apple dropped them too) — groups are separated by space
/// and identified by the active tab + its tooltip. Native `.help` tooltips
/// don't fire in a non-key panel, so glyph names use a custom overlay.
struct InlineBrowserView: View {
    @ObservedObject var browser: EmojiBrowserViewModel
    let onPick: (Emoji) -> Void
    let onCategory: (EmojiCategory) -> Void

    @State private var activeCategory: String?
    @State private var hoverIndex: Int?
    @State private var tooltipIndex: Int?
    @State private var hoverWork: DispatchWorkItem?

    private static let space = "browserGrid"
    private static let tabBarHeight: CGFloat = 56
    private static let tabIconHeight: CGFloat = 30
    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 36), spacing: 3),
        count: EmojiBrowserViewModel.columns
    )
    private var barTint: Color { Color(nsColor: .windowBackgroundColor) }

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
        // Rendered at the root so it can sit above the top row without being
        // clipped by the scroll view (the old bug put it in the next group).
        .overlayPreferenceValue(TooltipAnchorKey.self) { data in
            GeometryReader { proxy in
                if let data {
                    let rect = proxy[data.anchor]
                    tooltipBubble(data.text)
                        .fixedSize()
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
            categoryBar
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
            .font(.system(size: 25))  // match the pill's glyph size
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear)
            )
            // Index, not hexcode: the same emoji can appear in two sections,
            // so a hexcode id is ambiguous (the tooltip anchored to the wrong copy).
            .id("cell-\(index)")
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

    /// Light gray box matching the macOS system tooltip.
    private func tooltipBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.primary)
            .lineLimit(1)
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
        .frame(height: Self.tabIconHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Tall gradient region above the icons + breathing room below them.
        .padding(.top, 18)
        .padding(.bottom, 8)
        .background(barBackground)
    }

    /// A tall, severe gradient over a blurred base — the grid fades from fully
    /// visible at the top of the bar to the opaque strip the icons sit on,
    /// matching the macOS picker.
    private var barBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.5),
                        .init(color: .black, location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
            LinearGradient(
                stops: [
                    .init(color: barTint.opacity(0), location: 0.0),
                    .init(color: barTint.opacity(0.7), location: 0.45),
                    .init(color: barTint, location: 0.72),
                    .init(color: barTint, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

private struct SectionOffsetKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
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

enum BrowserLayout {
    static let width: CGFloat = 352
    static let height: CGFloat = 420
    static let cornerRadius: CGFloat = 12
}
