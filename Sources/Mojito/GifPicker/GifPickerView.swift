import SwiftUI

struct GifPickerView: View {
    /// Scroll anchor id used by `ScrollViewReader` to bring the "Load
    /// more" affordance into view when it owns the keyboard focus.
    static let loadMoreScrollID = "gif-picker-load-more"

    @ObservedObject var viewModel: GifPickerViewModel
    /// Called when the user picks a GIF (Enter / click).
    let onPick: (GifAsset) -> Void
    /// Called when the user dismisses (Esc / click-away).
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(height: GifPickerLayout.contentHeight)
            Divider().opacity(0.4)
            footer
        }
        .frame(width: GifPickerLayout.width)
    }

    @ViewBuilder
    private var content: some View {
        if let message = viewModel.errorMessage {
            errorState(message)
        } else if viewModel.results.isEmpty {
            placeholder(text: viewModel.query.isEmpty
                        ? String(localized: "Type to search GIFs.")
                        : String(localized: "Searching…"))
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: viewModel.columns),
                    spacing: 8
                ) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, asset in
                        GifThumb(
                            asset: asset,
                            isSelected: index == viewModel.selectedIndex
                        )
                        .id(index)
                        .onTapGesture {
                            viewModel.selectedIndex = index
                            onPick(asset)
                        }
                        .onAppear {
                            // Lazy-paginate: when one of the last few cells
                            // becomes visible, kick the next page request.
                            if index >= viewModel.results.count - 3 {
                                viewModel.loadMoreIfNeeded()
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, viewModel.canLoadMore ? 4 : 10)

                if viewModel.canLoadMore {
                    Button {
                        viewModel.loadMore()
                    } label: {
                        Text("Load more")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.regular)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                viewModel.isLoadMoreFocused ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                            // Bordered button has its own inset corner — the
                            // ring sits just outside it, matching cell rings.
                            .padding(-2)
                    )
                    .id(GifPickerView.loadMoreScrollID)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
            .scrollIndicators(.never)
            // Minimal scroll: no anchor → SwiftUI only scrolls if the cell
            // is offscreen, and stops as soon as it's visible. Wrapping in
            // `withAnimation` also captured the selection-ring transition
            // and made it lag behind the scroll.
            .onChange(of: viewModel.selectedIndex) { _, new in
                if viewModel.isLoadMoreFocused {
                    proxy.scrollTo(GifPickerView.loadMoreScrollID)
                } else {
                    proxy.scrollTo(new)
                }
            }
            // After a pagination append, selectedIndex's numeric value
            // didn't change (it sat at the old `results.count`, which is
            // now the first new GIF), so `onChange(of: selectedIndex)`
            // doesn't fire. Watch the count instead and nudge focus into
            // view so the user sees the new selection.
            .onChange(of: viewModel.results.count) { _, _ in
                if !viewModel.isLoadMoreFocused {
                    proxy.scrollTo(viewModel.selectedIndex)
                }
            }
        }
    }

    private func placeholder(text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            if viewModel.lastSearchFailed {
                Button(String(localized: "Try Again")) {
                    viewModel.retrySearch()
                }
                .controlSize(.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HintsFooter([
            KeyHint("↑↓"),
            KeyHint("←→"),
            KeyHint("↵", "insert"),
            KeyHint("esc", "dismiss"),
        ]) {
            (
                Text(verbatim: "Powered by ").font(.system(size: 10))
                + Text(verbatim: "GIPHY").font(.system(size: 12, weight: .bold)).tracking(-0.4)
            )
            .foregroundStyle(.secondary)
            .fixedSize()
        }
    }
}

private struct GifThumb: View {
    let asset: GifAsset
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        // Square cells keep the selection ring flush against the cell
        // extent. The GIF inside still uses its natural aspect ratio,
        // letterboxed into the square — symmetric margins read as
        // intentional even when the source GIF is portrait/landscape.
        AnimatedGifView(url: asset.thumbURL, cornerRadius: 6)
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 2)
            )
            .onHover { isHovered = $0 }
            .accessibilityLabel(Text(verbatim: asset.title))
    }

    private var borderColor: Color {
        if isSelected { return .accentColor }
        // Match the emoji picker's row highlight so hover feels consistent.
        if isHovered { return Color(nsColor: .unemphasizedSelectedContentBackgroundColor) }
        return .clear
    }
}

enum GifPickerLayout {
    static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 12
    /// Sized to show ~3.5 rows of the 3-col grid — a partial 4th row
    /// hints at scrollability without dominating screen real estate.
    static let contentHeight: CGFloat = 400
    /// Total panel height: contentHeight + divider + footer + chrome.
    static let panelHeight: CGFloat = 440
}
