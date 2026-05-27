import SwiftUI

struct PickerView: View {
    @ObservedObject var viewModel: PickerViewModel

    var body: some View {
        // Chrome lives on the panel (NSGlassEffectView / NSVisualEffectView)
        // so we match NSMenu pixel-faithfully.
        VStack(spacing: 0) {
            if viewModel.results.isEmpty {
                emptyState
            } else {
                resultsList
                Divider().opacity(0.3)
                footer
            }
        }
        .frame(width: PickerLayout.width)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.offset) { index, scored in
                        PickerRow(scored: scored, index: index, viewModel: viewModel)
                            .id(index)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
            .scrollIndicators(.never)
            .frame(
                height: CGFloat(min(viewModel.results.count, PickerLayout.maxVisibleRows)) * PickerLayout.rowHeight + 8
            )
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                proxy.scrollTo(newIndex, anchor: nil)
            }
            .onChange(of: viewModel.query) { _, _ in
                proxy.scrollTo(0, anchor: .top)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            footerHint(key: "↑↓", label: "select")
            footerHint(key: "↵", label: "insert")
            footerHint(key: "esc", label: "dismiss")
            Spacer()
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func footerHint(key: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(label)
        }
    }

    private var emptyState: some View {
        Text("No emoji for :\(viewModel.query):")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Per-row `@ObservedObject` so the highlight moves on `selectedIndex`
/// changes. Without it, the `ForEach id + .id(index)` dual identity
/// inside `LazyVStack` confused SwiftUI's diff.
private struct PickerRow: View {
    static let dogcowImage: NSImage? = {
        guard let image = ImageBlob.load("v01") else { return nil }
        image.isTemplate = true
        return image
    }()

    let scored: ScoredEmoji
    let index: Int
    @ObservedObject var viewModel: PickerViewModel

    var body: some View {
        let isSelected = (index == viewModel.selectedIndex)
        HStack(spacing: 10) {
            leadingGlyph
                .frame(width: 24)
            label
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // Neutral gray, not accent-tinted — matches the macOS emoji
            // picker's selected-row style.
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : .clear)
                .padding(.horizontal, 4)
        )
    }

    /// Defaults to the Text glyph; eggs that need a custom asset
    /// (dogcow) render an Image.
    @ViewBuilder
    private var leadingGlyph: some View {
        if scored.emoji.hexcode == FuzzyMatcher.k03Hex,
           let nsImage = Self.dogcowImage {
            // Template picks up the current foreground color.
            return AnyView(
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.primary)
            )
        } else {
            // Preview with the user's chosen skin tone.
            let display = scored.emoji.supportsSkinTone
                ? SkinTone.current.apply(to: scored.emoji.character)
                : scored.emoji.character
            return AnyView(
                Text(display)
                    .font(.system(size: 18))
            )
        }
    }

    @ViewBuilder
    private var label: some View {
        if FuzzyMatcher.rainbowHexcodes.contains(scored.emoji.hexcode) {
            rainbowLabel(scored.matchedShortcode)
        } else if FuzzyMatcher.pinnedHexcodes.contains(scored.emoji.hexcode) {
            // Non-rainbow pinned eggs surface as `???` to stay a surprise.
            Text("???")
                .font(.system(size: 13, weight: .medium))
                .italic()
                .foregroundStyle(.secondary)
        } else {
            highlightedShortcode(scored.matchedShortcode, query: viewModel.query)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Two color cycles tiled across 2 units; sliding endpoints left as
    /// `phase` advances 0→1 makes colors flow right-to-left. Wrap is
    /// seamless because the second cycle matches the first.
    @ViewBuilder
    private func rainbowLabel(_ text: String) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let phase = CGFloat(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.0))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .italic()
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            .red, .orange, .yellow, .green, .blue, .purple,
                            .red, .orange, .yellow, .green, .blue, .purple
                        ],
                        startPoint: UnitPoint(x: -phase, y: 0.5),
                        endPoint: UnitPoint(x: 2 - phase, y: 0.5)
                    )
                )
        }
    }

    private func highlightedShortcode(_ shortcode: String, query: String) -> Text {
        let q = query.lowercased()
        guard !q.isEmpty, let range = shortcode.lowercased().range(of: q) else {
            return Text(verbatim: ":\(shortcode):").foregroundStyle(.secondary)
        }
        let prefix = String(shortcode[shortcode.startIndex..<range.lowerBound])
        let middle = String(shortcode[range])
        let suffix = String(shortcode[range.upperBound..<shortcode.endIndex])
        return (
            Text(verbatim: ":").foregroundStyle(.secondary)
            + Text(prefix).foregroundStyle(.secondary)
            + Text(middle).foregroundStyle(.primary).bold()
            + Text(suffix).foregroundStyle(.secondary)
            + Text(verbatim: ":").foregroundStyle(.secondary)
        )
    }
}

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
