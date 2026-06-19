import SwiftUI
import KeyboardShortcuts

/// The Quick Access trigger picker, the 8-slot favorites editor, and the
/// global emoji-browser hotkey. The shortcut follows the Emoji trigger
/// (`:` → `:?`) by default but can be set to any preset or custom trigger.
struct QuickAccessSection: View {
    @Binding var enabled: Bool
    @Binding var open: String
    @Binding var followEmoji: Bool
    /// The current Emoji open, used to render the "follow" option's `:?` label.
    let emojiOpen: String
    /// Opens claimed by the other active triggers — grayed in the picker.
    let takenOpens: Set<String>

    @StateObject private var store = QuickAccessStore.shared
    @State private var editing: EditingSlot?
    @State private var hovered: Int?
    @State private var resetHovered = false
    @State private var confirmReset = false
    private let database = EmojiDatabase.shared

    private var usage: [String: Int] {
        (UserDefaults.standard.dictionary(forKey: PrefsKey.usageCounts) as? [String: Int]) ?? [:]
    }

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Access")
                    Text("Pop up a pill of your favorite and most-used emoji.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)

            if enabled {
                TriggerPicker(
                    mode: .quickAccess,
                    open: $open,
                    takenOpens: takenOpens,
                    defaultOpen: TriggerConfig.default.quickAccess.open,
                    sameAsEmoji: $followEmoji,
                    followLabel: "\(emojiOpen)?",
                    defaultFollowsEmoji: true
                )
            }

            slotGrid

            LabeledContent("Emoji Browser shortcut") {
                KeyboardShortcuts.Recorder("", name: .showEmojiBrowser)
            }
        }
        .sheet(item: $editing) { slot in
            QuickAccessBrowserSheet { emoji in store.pin(emoji.hexcode, at: slot.id) }
        }
    }

    private var slotGrid: some View {
        let slots = QuickAccess.resolvedPerSlot(store: store, database: database, usage: usage)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Mirror the live pill: a glassy capsule of cells.
                HStack(spacing: 2) {
                    ForEach(0..<QuickAccessStore.slotCount, id: \.self) { index in
                        slotCell(index: index, slot: slots[index])
                    }
                }
                .padding(6)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .textBackgroundColor))
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                )

                Spacer(minLength: 0)

                if store.hasPins {
                    Button("Reset") { confirmReset = true }
                        .confirmationDialog(
                            "Reset all pinned slots to most-used?",
                            isPresented: $confirmReset,
                            titleVisibility: .visible
                        ) {
                            Button("Reset", role: .destructive) { store.resetAll() }
                            Button("Cancel", role: .cancel) {}
                        }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Click a slot to pin a specific emoji or symbol.")
                Text("Quick Access defaults to your most-used emoji.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func slotCell(index: Int, slot: ResolvedSlot) -> some View {
        let isHovered = hovered == index
        let isFirst = index == 0
        let isLast = index == QuickAccessStore.slotCount - 1
        return ZStack {
            if isHovered {
                // End cells round their outer edge to nest in the capsule ends.
                UnevenRoundedRectangle(
                    topLeadingRadius: isFirst ? 17 : 8,
                    bottomLeadingRadius: isFirst ? 17 : 8,
                    bottomTrailingRadius: isLast ? 17 : 8,
                    topTrailingRadius: isLast ? 17 : 8,
                    style: .continuous
                )
                .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
            }
            if let emoji = slot.emoji {
                Text(displayGlyph(emoji)).font(.system(size: 22))
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 34, height: 34)
        .overlay(alignment: .topTrailing) { cornerControl(index: index, slot: slot).padding(2) }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture { editing = EditingSlot(id: index) }
        .onHover { inside in hovered = inside ? index : (hovered == index ? nil : hovered) }
        .help(slotHelp(slot))
    }

    /// Pinned slots wear a subtle orange pin; hovering one swaps it for an
    /// `×` button whose background darkens on hover to read as clickable.
    @ViewBuilder
    private func cornerControl(index: Int, slot: ResolvedSlot) -> some View {
        if slot.pinned {
            if hovered == index {
                Button { store.reset(at: index) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(Color.black.opacity(resetHovered ? 0.7 : 0.45)))
                }
                .buttonStyle(.plain)
                .onHover { resetHovered = $0 }
                .help("Reset to most-used")
            } else {
                Image(systemName: "pin.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(2)
                    .background(Circle().fill(Color.orange.opacity(0.18)))
            }
        }
    }

    private func slotHelp(_ slot: ResolvedSlot) -> String {
        if slot.pinned, let emoji = slot.emoji {
            return String(localized: "Pinned :\(emoji.primaryShortcode): — click to change")
        }
        return String(localized: "Most-used — click to pin a specific emoji")
    }

    private func displayGlyph(_ emoji: Emoji) -> String {
        emoji.tonedGlyph
    }
}

struct EditingSlot: Identifiable { let id: Int }

/// Pins a slot using the same emoji browser the rest of the app uses, hosted
/// in a sheet (with its search field made editable for the key window).
private struct QuickAccessBrowserSheet: View {
    let onPick: (Emoji) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = EmojiBrowserViewModel(
        database: .shared, quickAccess: .shared
    )

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pick an emoji").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider()
            InlineBrowserView(
                browser: browser,
                onPick: { emoji in onPick(emoji); dismiss() },
                onCategory: { browser.selectCategory($0) },
                editableSearch: true
            )
        }
        .frame(width: BrowserLayout.width, height: BrowserLayout.height + 48)
    }
}
