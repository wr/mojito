import SwiftUI
import KeyboardShortcuts

/// "Quick access" — how the pill is summoned and the global browser hotkey.
struct QuickAccessSection: View {
    @AppStorage(PrefsKey.favoritesTrigger) private var triggerRaw: String = FavoritesTrigger.question.rawValue
    @AppStorage(PrefsKey.favoritesTriggerSurface) private var surfaceRaw: String = FavoritesTriggerSurface.pill.rawValue

    var body: some View {
        Section {
            LabeledContent("Quick access shortcut") {
                Menu {
                    ForEach(FavoritesTrigger.allCases) { trigger in
                        Button {
                            triggerRaw = trigger.rawValue
                        } label: {
                            if trigger.rawValue == triggerRaw {
                                Label(trigger.settingsLabel, systemImage: "checkmark")
                            } else {
                                Text(trigger.settingsLabel)
                            }
                        }
                    }
                } label: {
                    triggerCaps(FavoritesTrigger.from(triggerRaw))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if triggerRaw != FavoritesTrigger.off.rawValue {
                Picker("Shows", selection: $surfaceRaw) {
                    ForEach(FavoritesTriggerSurface.allCases) { surface in
                        Text(surface.settingsLabel).tag(surface.rawValue)
                    }
                }
            }

            LabeledContent("Emoji browser shortcut") {
                KeyboardShortcuts.Recorder("", name: .showEmojiBrowser)
            }
        } header: {
            Text("Quick access")
        } footer: {
            Text("Type the shortcut to pop the Top 8 below. Return inserts the first; ←→ pick another; ↓ opens the full browser.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func triggerCaps(_ trigger: FavoritesTrigger) -> some View {
        switch trigger {
        case .off:
            Text("Off").foregroundStyle(.secondary)
        case .colon:
            HStack(spacing: 4) {
                KeyCap(":")
                Text("then pause").font(.callout).foregroundStyle(.secondary)
            }
        case .question:
            HStack(spacing: 3) { KeyCap(":"); KeyCap("?") }
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(0..<QuickAccessStore.slotCount, id: \.self) { index in
                        slotCell(index: index, slot: slots[index])
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Click a slot to pin a specific emoji; hover a pinned slot to reset it.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if store.hasPins {
                        Button("Reset all") { store.resetAll() }
                            .buttonStyle(.borderless)
                            .font(.callout)
                    }
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Top 8")
        }
        .sheet(item: $editing) { slot in
            QuickAccessBrowserSheet { emoji in store.pin(emoji.hexcode, at: slot.id) }
        }
    }

    private func slotCell(index: Int, slot: ResolvedSlot) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if let emoji = slot.emoji {
                Text(displayGlyph(emoji)).font(.system(size: 22))
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 38, height: 38)
        .contentShape(Rectangle())
        .onTapGesture { editing = EditingSlot(id: index) }
        .onHover { inside in hovered = inside ? index : (hovered == index ? nil : hovered) }
        .overlay(alignment: .topTrailing) { badge(index: index, slot: slot) }
        .help(slotHelp(slot))
    }

    /// Pinned slots show a pin; hovering one swaps it for a reset control.
    @ViewBuilder
    private func badge(index: Int, slot: ResolvedSlot) -> some View {
        if slot.pinned {
            Group {
                if hovered == index {
                    Button { store.reset(at: index) } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                    }
                    .buttonStyle(.plain)
                    .help("Reset to most-used")
                } else {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(3)
                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
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

/// A small keycap, e.g. `:` or `?`, for the trigger display.
private struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .frame(minWidth: 15)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            )
    }
}
