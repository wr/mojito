import SwiftUI

/// Full-library grid browser. Opened from the bare-`:` picker's "Browse all
/// emojis…" row or the menu bar. A real key window (unlike the inline
/// picker), so the search field and clicks work the ordinary AppKit way;
/// the controller returns focus to the prior app and types the pick.
struct EmojiBrowserView: View {
    @ObservedObject var viewModel: EmojiBrowserViewModel
    let onPick: (Emoji) -> Void
    let onDismiss: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var hoveredHexcode: String?

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 34), spacing: 4),
        count: 9
    )

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            grid
            Divider()
            categoryBar
        }
        .frame(minWidth: 380, minHeight: 360)
        .background(.background)
        // Esc closes the window even when the search field has focus.
        .onExitCommand(perform: onDismiss)
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search emoji", text: $viewModel.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit {
                    if let top = viewModel.topResult { onPick(top) }
                }
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6, pinnedViews: [.sectionHeaders]) {
                    let sections = viewModel.displaySections
                    if sections.isEmpty {
                        emptyResults
                    } else {
                        ForEach(sections) { section in
                            Section {
                                LazyVGrid(columns: columns, spacing: 4) {
                                    ForEach(section.emoji) { emoji in
                                        cell(for: emoji)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.bottom, 6)
                            } header: {
                                sectionHeader(section.category.title)
                                    .id(section.category.id)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
            .onChange(of: viewModel.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    private func cell(for emoji: Emoji) -> some View {
        let display = emoji.supportsSkinTone
            ? SkinTone.current.apply(to: emoji.character)
            : emoji.character
        let isHovered = hoveredHexcode == emoji.hexcode
        return Button {
            onPick(emoji)
        } label: {
            Text(display)
                .font(.system(size: 24))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovered
                              ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                              : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(":\(emoji.primaryShortcode):")
        .onHover { hovering in
            hoveredHexcode = hovering ? emoji.hexcode : (hoveredHexcode == emoji.hexcode ? nil : hoveredHexcode)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.bar)
    }

    private var emptyResults: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No emoji matching “\(viewModel.query)”")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var categoryBar: some View {
        HStack(spacing: 2) {
            ForEach(viewModel.visibleCategories) { category in
                Button {
                    viewModel.scroll(to: category)
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
