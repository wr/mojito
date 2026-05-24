import SwiftUI
import AppKit

/// Stats + Easter eggs settings pane. Lifted out of About so the About
/// page can stay focused on the app/donation/credits.
struct EasterEggsSettingsView: View {
    /// Observed so `engine.clearUsageStats()` re-renders the stats block.
    @EnvironmentObject private var engine: Engine
    @State private var justCopied = false
    /// Bumped on `.easterEggDiscovered` so the section re-evaluates
    /// `EasterEggTracker.isDiscovered(_:)` while the pane is open.
    @State private var easterEggsTick: Int = 0

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

    private var topEmoji: [String] {
        usageCounts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(8)
            .compactMap { EmojiDatabase.shared.byHexcode[$0.key]?.character }
    }

    var body: some View {
        Form {
            Section("Stats") {
                LabeledContent("User since", value: firstLaunchDate)
                    .padding(.vertical, rowPadding)
                LabeledContent("Emoji autocompleted", value: "\(totalAutocompleted)")
                    .padding(.vertical, rowPadding)
                topEightRow
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
    }

    // MARK: - Easter eggs

    /// Scrambled Dogcow tile (`v01.bin`) used in the `:moof:` row.
    private static let dogcowImage: NSImage? = {
        guard let image = ImageBlob.load("v01") else { return nil }
        image.isTemplate = true
        return image
    }()

    private var easterEggsSection: some View {
        Section {
            let _ = easterEggsTick
            ForEach(EasterEgg.allCases) { egg in
                easterEggRow(egg, discovered: EasterEggTracker.isDiscovered(egg))
                    .padding(.vertical, rowPadding)
            }
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

    /// Returns the detail string for a discovered egg, with a per-egg
    /// inline metric where applicable. Perfect Bounce shows the running
    /// corner-hit count from `PrefsKey.perfectBounceCount`.
    private func detailText(for egg: EasterEgg) -> String {
        switch egg {
        case .perfectBounce:
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
                } else if egg == .moof, let nsImage = Self.dogcowImage {
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

    // MARK: - Top 8 (tile row)

    private var topEightRow: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("Your top 8")
                Spacer()
                if topEmoji.isEmpty {
                    Text("Type some emoji and they'll show up here.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    HStack(spacing: 4) {
                        ForEach(0..<8, id: \.self) { index in
                            Group {
                                if index < topEmoji.count {
                                    Text(topEmoji[index])
                                        .font(.system(size: 22))
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                        }
                    }
                }
            }
            Button(justCopied ? "Copied!" : "Copy") {
                copyTopEmoji()
            }
            .disabled(topEmoji.isEmpty)
        }
    }

    private func copyTopEmoji() {
        let payload = "My top 8 emoji: \(topEmoji.joined())"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        justCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            justCopied = false
        }
    }
}
