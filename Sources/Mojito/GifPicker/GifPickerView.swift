import SwiftUI

struct GifPickerView: View {
    @ObservedObject var viewModel: GifPickerViewModel
    /// Called when the user picks a GIF (Enter / click).
    let onPick: (GifAsset) -> Void
    /// Called when the user dismisses (Esc / click-away).
    let onDismiss: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)
            Divider().opacity(0.4)
            content
                .frame(height: 320)
            Divider().opacity(0.4)
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(width: GifPickerLayout.width)
        .onAppear { fieldFocused = true }
        .onExitCommand { onDismiss() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                "Search GIFs…",
                text: $viewModel.query
            )
            .textFieldStyle(.plain)
            .focused($fieldFocused)
            .font(.system(size: 14))
            .onKeyPress(.return) {
                if let asset = viewModel.selectedAsset() {
                    onPick(asset)
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.upArrow) {
                viewModel.moveSelection(.up)
                return .handled
            }
            .onKeyPress(.downArrow) {
                viewModel.moveSelection(.down)
                return .handled
            }
            .onKeyPress(.leftArrow) {
                guard !viewModel.query.isEmpty else { return .ignored }
                // Only intercept when results are showing AND caret isn't
                // mid-edit — but the simple form here always navigates.
                // If the user wants to edit, they'll click in the field.
                viewModel.moveSelection(.left)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                guard !viewModel.query.isEmpty else { return .ignored }
                viewModel.moveSelection(.right)
                return .handled
            }
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let message = viewModel.errorMessage {
            placeholder(text: message)
        } else if viewModel.results.isEmpty {
            placeholder(text: viewModel.query.isEmpty
                        ? String(localized: "Type to search GIFs.")
                        : String(localized: "Searching…"))
        } else {
            grid
        }
    }

    private var grid: some View {
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
                    .onTapGesture {
                        viewModel.selectedIndex = index
                        onPick(asset)
                    }
                }
            }
            .padding(10)
        }
        .scrollIndicators(.never)
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

    private var footer: some View {
        HStack(spacing: 12) {
            footerHint(key: "↑↓←→", label: "navigate")
            footerHint(key: "↵", label: "copy")
            footerHint(key: "esc", label: "dismiss")
            Spacer()
            Text(verbatim: "Powered by GIPHY")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private func footerHint(key: String, label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(label)
        }
    }
}

private struct GifThumb: View {
    let asset: GifAsset
    let isSelected: Bool

    var body: some View {
        AnimatedGifView(url: asset.thumbURL, cornerRadius: 6)
            .frame(height: 90)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .accessibilityLabel(Text(verbatim: asset.title))
    }
}

enum GifPickerLayout {
    static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 12
}
