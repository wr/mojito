import SwiftUI

/// The full-library grid, shown by *growing the picker panel* (not a separate
/// window). Driven by the trigger state machine through `EmojiBrowserViewModel`
/// — the panel stays non-key so the focused app keeps its insertion point and
/// picks are typed straight in.
///
/// No section titles (Apple dropped them too) — groups are separated by space
/// and identified by the active tab + a hover tooltip. The panel is non-key,
/// so native `.help` tooltips don't fire; glyph names use a custom overlay.
struct InlineBrowserView: View {
    @ObservedObject var browser: EmojiBrowserViewModel
    let onPick: (Emoji) -> Void
    let onCategory: (EmojiCategory) -> Void

    @State private var activeCategory: String?
    @State private var hoverIndex: Int?
    @State private var tooltipIndex: Int?
    @State private var hoverWork: DispatchWorkItem?
    /// The caret only blinks once the search row is clicked (or text exists),
    /// so it doesn't imply a focusable field before then.
    @State private var searchClicked = false

    private static let space = "browserGrid"
    private static let tabBarHeight: CGFloat = 56
    private static let tabIconHeight: CGFloat = 30
    private static let cellSpacing: CGFloat = 3
    private static let cellHeight: CGFloat = 40
    private static let groupGap: CGFloat = 28

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
            // Caret reserves its slot always (hidden via opacity) so showing
            // it on click doesn't shift the placeholder.
            caret
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
        .frame(width: 2)  // fixed slot — no layout shift when it appears
    }

    // MARK: Grid

    private var gridWithBar: some View {
        ZStack(alignment: .bottom) {
            grid
            categoryBar
        }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Deliberately NON-lazy (plain VStack of manual rows, no
                // LazyVGrid). The corpus is fixed (~1900 glyphs), so laying it
                // all out costs a small one-time hit on open but makes every
                // row's offset *real* — that's what makes `scrollTo` exact and
                // the active-tab tracking truthful. Lazy height estimation was
                // the root of the drifting-scroll bug.
                VStack(alignment: .leading, spacing: Self.groupGap) {
                    if browser.sections.isEmpty {
                        emptyResults
                    } else {
                        ForEach(indexedSections, id: \.section.id) { entry in
                            grp(entry)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, Self.tabBarHeight + 4)  // clear the floating bar
            }
            .coordinateSpace(name: Self.space)
            .onPreferenceChange(SectionTopKey.self) { tops in
                guard browser.query.isEmpty else { activeCategory = nil; return }
                let atTop = tops.filter { $0.value <= 16 }.max { $0.value < $1.value }
                activeCategory = atTop?.key ?? tops.min { $0.value < $1.value }?.key
            }
            .onChange(of: browser.scrollTarget) { _, target in
                guard let target else { return }
                // Offsets are real (non-lazy), so a single scrollTo lands exactly.
                switch target {
                case .section(let c): proxy.scrollTo(BrowserScroll.section(c), anchor: .top)
                case .cell(let i):    proxy.scrollTo(BrowserScroll.cell(i), anchor: nil)
                }
                DispatchQueue.main.async { browser.scrollTarget = nil }
            }
        }
    }

    /// Chunk a section's items into rows of `columns`.
    private func rows(_ items: [(index: Int, emoji: Emoji)]) -> [[(index: Int, emoji: Emoji)]] {
        stride(from: 0, to: items.count, by: EmojiBrowserViewModel.columns).map {
            Array(items[$0 ..< min($0 + EmojiBrowserViewModel.columns, items.count)])
        }
    }

    /// One section group: non-lazy rows + the scroll anchor + active-tab probe.
    private func grp(_ entry: (section: BrowserSection, items: [(index: Int, emoji: Emoji)])) -> some View {
        VStack(alignment: .leading, spacing: Self.cellSpacing) {
            ForEach(Array(rows(entry.items).enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.cellSpacing) {
                    ForEach(row, id: \.emoji.hexcode) { item in
                        cell(item.emoji, index: item.index)
                    }
                    // Pad a short final row so cells stay column-aligned.
                    if row.count < EmojiBrowserViewModel.columns {
                        ForEach(0 ..< (EmojiBrowserViewModel.columns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity).frame(height: Self.cellHeight)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .id(BrowserScroll.section(entry.section.category))
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: SectionTopKey.self,
                    value: [entry.section.category.id: geo.frame(in: .named(Self.space)).minY]
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
            .id(BrowserScroll.cell(index))
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

    /// Light box matching the macOS system tooltip.
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
                let isActive = browser.query.isEmpty && activeCategory == category.id
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
        .frame(height: Self.tabIconHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 18)   // tall gradient region above the icons
        .padding(.bottom, 8) // breathing room below
        .background(barBackground)
        .contentShape(Rectangle())  // eat clicks so they don't hit the grid
    }

    /// A frosted bar that stays glassy: just the blur, faded in from the top
    /// of the bar so the grid dissolves into it (no opaque color layer).
    private var barBackground: some View {
        Rectangle()
            .fill(.regularMaterial)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.85), location: 0.55),
                        .init(color: .black, location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
    }
}

/// Each group's top offset in the scroll viewport, so the active tab can
/// track the scroll position.
private struct SectionTopKey: PreferenceKey {
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
