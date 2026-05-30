import SwiftUI

/// The full-library grid, shown by *growing the picker panel* (not a separate
/// window). Driven by the trigger state machine through `EmojiBrowserViewModel`
/// — the panel stays non-key so the focused app keeps its insertion point and
/// picks are typed straight in.
///
/// Shows **one category at a time** (like the iOS emoji keyboard): the tab bar
/// switches which category is displayed; it never scrolls a long combined list.
/// So there's no `scrollTo`-to-offscreen-section to drift — a tab tap just
/// swaps the dataset and resets to the top. The panel is non-key, so native
/// `.help` tooltips don't fire; glyph names use a custom root overlay.
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

    private static let cellHeight: CGFloat = 40
    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 36), spacing: 3),
        count: EmojiBrowserViewModel.columns
    )

    /// Current emoji paired with their flat selection index.
    private var items: [(index: Int, emoji: Emoji)] {
        Array(browser.current.enumerated()).map { ($0.offset, $0.element) }
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

    // MARK: Grid (one category)

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if items.isEmpty {
                    emptyResults
                } else {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(items, id: \.emoji.hexcode) { item in
                            cell(item.emoji, index: item.index)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
            .onChange(of: browser.scrollTarget) { _, target in
                guard let target else { return }
                // Only ever scrolls within the current (short) category — to
                // the top on switch, or to an adjacent cell on keyboard nav.
                proxy.scrollTo(target, anchor: target == 0 ? .top : nil)
                DispatchQueue.main.async { browser.scrollTarget = nil }
            }
            // Reset to top whenever the shown category changes.
            .onChange(of: browser.selectedCategory) { _, _ in
                proxy.scrollTo(0, anchor: .top)
            }
        }
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
            .id(index)
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
                // Active = the shown category (cleared while searching).
                let isActive = !browser.isSearching && browser.selectedCategory == category
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

enum BrowserLayout {
    static let width: CGFloat = 352
    static let height: CGFloat = 420
    static let cornerRadius: CGFloat = 12
}
