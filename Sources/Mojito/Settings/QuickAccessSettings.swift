import SwiftUI
import KeyboardShortcuts

/// "Quick access" — the `:`-trigger shortcut and the global browser hotkey.
struct QuickAccessSection: View {
    @AppStorage(PrefsKey.quickAccessTriggerChar) private var triggerChar: String = "?"

    var body: some View {
        Section("Quick access") {
            LabeledContent("Quick access shortcut") {
                HStack(spacing: 5) {
                    KeyCap(":")
                    Text("+").font(.system(size: 12)).foregroundStyle(.tertiary)
                    TextField("?", text: $triggerChar)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 40)
                        .onChange(of: triggerChar) { _, new in
                            // A single punctuation/symbol char (letters/digits
                            // would shadow `:`-search; `:` would clash with `::`).
                            let valid = new.filter {
                                !($0.isLetter || $0.isNumber || $0.isWhitespace || "_-+:".contains($0))
                            }
                            let result = String(valid.suffix(1))
                            if result != new { triggerChar = result }
                        }
                }
            }

            LabeledContent("Emoji browser shortcut") {
                KeyboardShortcuts.Recorder("", name: .showEmojiBrowser)
            }
        }
    }
}

/// "Top 8" — the editable Quick Access slots. Each is auto (most-used) or
/// pinned to a specific emoji.
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(0..<QuickAccessStore.slotCount, id: \.self) { index in
                        slotCell(index: index, slot: slots[index])
                            .frame(maxWidth: .infinity)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Click a slot to pin a specific emoji. Hover a pinned slot to reset it back to your most frequently used.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if store.hasPins {
                        Button("Reset all") { store.resetAll() }
                            .buttonStyle(.borderless)
                            .font(.callout)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Top 8")
        }
        .sheet(item: $editing) { slot in
            QuickAccessBrowserSheet { emoji in store.pin(emoji.hexcode, at: slot.id) }
        }
    }

    private func slotCell(index: Int, slot: ResolvedSlot) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if let emoji = slot.emoji {
                Text(displayGlyph(emoji)).font(.system(size: 28))
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 50, height: 50)
        .contentShape(Rectangle())
        .onTapGesture { editing = EditingSlot(id: index) }
        .onHover { inside in hovered = inside ? index : (hovered == index ? nil : hovered) }
        .overlay(alignment: .topTrailing) { badge(index: index, slot: slot) }
        .help(slotHelp(slot))
    }

    /// Pinned slots show a red pin; hovering swaps it for a reset control.
    @ViewBuilder
    private func badge(index: Int, slot: ResolvedSlot) -> some View {
        if slot.pinned {
            Group {
                if hovered == index {
                    Button { store.reset(at: index) } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                    }
                    .buttonStyle(.plain)
                    .help("Reset to most-used")
                } else {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color.red))
                }
            }
            .offset(x: 6, y: -6)
        }
    }

    private func slotHelp(_ slot: ResolvedSlot) -> String {
        if slot.pinned, let emoji = slot.emoji {
            return "Pinned :\(emoji.primaryShortcode): — click to change"
        }
        return "Auto (most-used) — click to pin a specific emoji"
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

/// A small keycap, e.g. `:`, for the trigger display.
private struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .frame(minWidth: 16)
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
