import SwiftUI
import AppKit

struct EasterEggsSettingsView: View {
    /// Observed so `clearUsageStats()` re-renders the stats block.
    @EnvironmentObject private var engine: Engine
    /// Bumped on `.easterEggDiscovered` so the section re-renders while open.
    @State private var easterEggsTick: Int = 0
    @ObservedObject private var nav = SettingsNavigator.shared
    /// Row currently flashing (banner-click reveal), and its animated tint.
    @State private var flashEgg: String?
    @State private var flashOpacity: Double = 0

    private let rowPadding: CGFloat = 2

    private var firstLaunchDate: String {
        let ts = UserDefaults.standard.object(forKey: PrefsKey.firstLaunchDate) as? TimeInterval ?? Date().timeIntervalSince1970
        return Date(timeIntervalSince1970: ts)
            .formatted(.dateTime.month(.wide).day().year())
    }

    private var usageCounts: [String: Int] {
        (UserDefaults.standard.dictionary(forKey: PrefsKey.usageCounts) as? [String: Int]) ?? [:]
    }

    private var totalAutocompleted: Int {
        usageCounts.values.reduce(0, +)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section("Stats") {
                    LabeledContent("User since", value: firstLaunchDate)
                        .padding(.vertical, rowPadding)
                    LabeledContent("Emoji autocompleted", value: "\(totalAutocompleted)")
                        .padding(.vertical, rowPadding)
                    HStack {
                        Text("Danger zone")
                        Spacer()
                        ClearStatsButton(isDisabled: totalAutocompleted == 0)
                    }
                    .padding(.vertical, rowPadding)
                }

                easterEggsSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .onAppear { consumeReveal(proxy) }
            .onChange(of: nav.reveal) { _, _ in consumeReveal(proxy) }
        }
    }

    /// Scroll the banner-clicked egg into view and flash its row. A no-op
    /// unless `SettingsNavigator` has a pending reveal for a visible egg;
    /// clears the request once handled so it doesn't re-fire.
    private func consumeReveal(_ proxy: ScrollViewProxy) {
        guard let request = nav.reveal else { return }
        nav.reveal = nil
        let id = request.eggID
        guard EasterEggTracker.visibleCases.contains(where: { $0.id == id }) else { return }
        // Defer a tick so a freshly-mounted list has laid out its rows.
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(id, anchor: .center)
            }
            // Commit the lit tint first; animate it away on the next tick so
            // the two state writes don't coalesce into a no-op render.
            flashEgg = id
            flashOpacity = 0.5
            DispatchQueue.main.async {
                // Ends dim: 0.5 → 0 → 0.5 → 0 (odd count settles on the target).
                withAnimation(.easeInOut(duration: 0.5).repeatCount(3, autoreverses: true)) {
                    flashOpacity = 0
                }
            }
        }
    }

    // MARK: - Easter eggs

    /// Scrambled Dogcow tile (`v01.bin`).
    private static let dogcowImage: NSImage? = {
        guard let image = ImageBlob.load("v01") else { return nil }
        image.isTemplate = true
        return image
    }()

    private var easterEggsSection: some View {
        Section {
            let _ = easterEggsTick
            ForEach(EasterEggTracker.visibleCases) { egg in
                easterEggRow(egg, discovered: EasterEggTracker.isDiscovered(egg))
                    .padding(.vertical, rowPadding)
                    .padding(.leading, EasterEggTracker.isChildKeyword(egg) ? 20 : 0)
                    .background(flashBackground(for: egg))
                    .id(egg.id)
            }
            HStack {
                Text("Danger zone")
                Spacer()
                ResetEasterEggsButton(isDisabled: EasterEggTracker.discoveredCount == 0)
            }
            .padding(.vertical, rowPadding)
        } header: {
            HStack {
                Text("Easter eggs")
                Spacer()
                Text("\(EasterEggTracker.discoveredCount) of \(EasterEggTracker.totalCount)")
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .easterEggDiscovered)) { _ in
            easterEggsTick &+= 1
        }
    }

    /// Transient tint behind a row being revealed from a banner click.
    @ViewBuilder
    private func flashBackground(for egg: EasterEgg) -> some View {
        if flashEgg == egg.id {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(flashOpacity))
                .padding(.horizontal, -8)
                .allowsHitTesting(false)
        }
    }

    private func easterEggRow(_ egg: EasterEgg, discovered: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            easterEggTile(egg, discovered: discovered)

            VStack(alignment: .leading, spacing: 2) {
                if discovered {
                    Text(egg.title)
                    Text(.init(detailText(for: egg)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("???")
                        .foregroundStyle(.secondary)
                    Text(egg.hint)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if discovered {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
            }
        }
    }

    /// Perfect Bounce appends a running corner-hit count.
    private func detailText(for egg: EasterEgg) -> String {
        switch egg {
        case .k31:
            let count = UserDefaults.standard.integer(forKey: PrefsKey.perfectBounceCount)
            return egg.detail + " (\(count))"
        default:
            return egg.detail
        }
    }

    @ViewBuilder
    private func easterEggTile(_ egg: EasterEgg, discovered: Bool) -> some View {
        let tileSize: CGFloat = 36
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(discovered ? 0.08 : 0.05))

            if discovered {
                if let glyph = egg.emojiGlyph {
                    Text(glyph)
                        .font(.system(size: 22))
                } else if egg == .k03, let nsImage = Self.dogcowImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .foregroundStyle(.primary)
                }
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: tileSize, height: tileSize)
    }

}

// MARK: - Reset eggs button

/// Parallels `ClearStatsButton`.
struct ResetEasterEggsButton: View {
    @State private var confirm = false
    var isDisabled: Bool = false

    var body: some View {
        Button("Reset eggs...") { confirm = true }
            .disabled(isDisabled)
            .confirmationDialog(
                "Reset all easter egg progress?",
                isPresented: $confirm,
                titleVisibility: .visible
            ) {
                Button("Reset eggs", role: .destructive) {
                    EasterEggTracker.reset()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will erase your discovery progress and any per-egg counters. The eggs themselves still work — you'll just need to find them again.")
            }
    }
}
