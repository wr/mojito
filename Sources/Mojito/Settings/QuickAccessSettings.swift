import SwiftUI
import KeyboardShortcuts

/// "Quick access" — the (fixed) `:?` trigger and the global browser hotkey.
struct QuickAccessSection: View {
    var body: some View {
        Section("Quick access") {
            LabeledContent("Quick access shortcut") {
                HStack(spacing: 4) { KeyCap(":"); KeyCap("?") }
            }
            LabeledContent("Emoji browser shortcut") {
                KeyboardShortcuts.Recorder("", name: .showEmojiBrowser)
            }
        }
    }
}

/// "Top 8" — the editable Quick Access slots. Each fills with a most-used
/// emoji unless the user pins a specific one.
struct TopEightSection: View {
    @StateObject private var store = QuickAccessStore.shared
    @State private var editing: EditingSlot?
    @State private var hovered: Int?
    private let database = EmojiDatabase.shared

    private var usage: [String: Int] {
        (UserDefaults.standard.dictionary(forKey: PrefsKey.usageCounts) as? [String: Int]) ?? [:]
    }

    var body: some View {
        let slots = QuickAccess.resolvedPerSlot(store: store, database: database, usage: usage)
        Section {
            HStack(spacing: 8) {
                ForEach(0..<QuickAccessStore.slotCount, id: \.self) { index in
                    slotCell(index: index, slot: slots[index])
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
        } header: {
            HStack(spacing: 8) {
                Text("Top 8")
                Spacer()
                if store.hasPins {
                    Button("Reset all") { store.resetAll() }
                        .buttonStyle(.borderless)
                        .font(.callout)
                        .textCase(nil)
                }
            }
        } footer: {
            Text("Each slot fills with one of your most-used emoji. Click a slot to pin a specific one instead; hover a pinned slot to set it back to most-used.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $editing) { slot in
            QuickAccessBrowserSheet { emoji in store.pin(emoji.hexcode, at: slot.id) }
        }
    }

    private func slotCell(index: Int, slot: ResolvedSlot) -> some View {
        let isHovered = hovered == index
        return RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color.primary.opacity(isHovered ? 0.12 : 0.05))
            .frame(width: 50, height: 50)
            .overlay {
                if let emoji = slot.emoji {
                    Text(displayGlyph(emoji)).font(.system(size: 28))
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .overlay(alignment: .topTrailing) { cornerControl(index: index, slot: slot) }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .onTapGesture { editing = EditingSlot(id: index) }
            .onHover { inside in hovered = inside ? index : (hovered == index ? nil : hovered) }
            .help(slotHelp(slot))
    }

    /// Pinned slots wear a red pin; hovering one swaps it for a reset button.
    @ViewBuilder
    private func cornerControl(index: Int, slot: ResolvedSlot) -> some View {
        if slot.pinned {
            Group {
                if hovered == index {
                    Button { store.reset(at: index) } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary, Color(nsColor: .windowBackgroundColor))
                    }
                    .buttonStyle(.plain)
                    .help("Set back to most-used")
                } else {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(.red))
                }
            }
            .padding(4)
        }
    }

    private func slotHelp(_ slot: ResolvedSlot) -> String {
        if slot.pinned, let emoji = slot.emoji {
            return "Pinned :\(emoji.primaryShortcode): — click to change"
        }
        return "Most-used — click to pin a specific emoji"
    }

    private func displayGlyph(_ emoji: Emoji) -> String {
        emoji.supportsSkinTone ? SkinTone.current.apply(to: emoji.character) : emoji.character
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

/// A small keycap, e.g. `:` or `?`, for the shortcut display.
private struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .frame(minWidth: 18)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            )
    }
}
