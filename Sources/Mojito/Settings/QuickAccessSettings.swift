import SwiftUI

/// The "Quick Access" section of General settings: how the pill is triggered,
/// what it surfaces, and the 8 editable slots (each auto/most-used or a pinned
/// emoji).
struct QuickAccessSection: View {
    @AppStorage(PrefsKey.favoritesTrigger) private var triggerRaw: String = FavoritesTrigger.question.rawValue
    @AppStorage(PrefsKey.favoritesTriggerSurface) private var surfaceRaw: String = FavoritesTriggerSurface.pill.rawValue

    var body: some View {
        Section {
            Picker("Trigger", selection: $triggerRaw) {
                ForEach(FavoritesTrigger.allCases) { trigger in
                    Text(trigger.settingsLabel).tag(trigger.rawValue)
                }
            }
            if triggerRaw != FavoritesTrigger.off.rawValue {
                Picker("Shows", selection: $surfaceRaw) {
                    ForEach(FavoritesTriggerSurface.allCases) { surface in
                        Text(surface.settingsLabel).tag(surface.rawValue)
                    }
                }
            }
            QuickAccessGrid()
        } header: {
            Text("Quick access")
        } footer: {
            Text("Each slot auto-fills with your most-used emoji, or click one to pin a specific emoji. Return inserts the first; ←→ pick another; ↓ opens the full browser.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EditingSlot: Identifiable { let id: Int }

private struct QuickAccessGrid: View {
    @StateObject private var store = QuickAccessStore.shared
    @State private var editing: EditingSlot?
    private let database = EmojiDatabase.shared

    private var usage: [String: Int] {
        (UserDefaults.standard.dictionary(forKey: PrefsKey.usageCounts) as? [String: Int]) ?? [:]
    }

    var body: some View {
        let slots = QuickAccess.resolvedPerSlot(store: store, database: database, usage: usage)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<QuickAccessStore.slotCount, id: \.self) { index in
                    slotCell(index: index, slot: slots[index])
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Click a slot to pin an emoji; ↺ resets it to most-used.")
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
        .sheet(item: $editing) { slot in
            EmojiPickerSheet { emoji in store.pin(emoji.hexcode, at: slot.id) }
        }
    }

    private func slotCell(index: Int, slot: ResolvedSlot) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(slot.pinned ? 0.10 : 0.05))
            if slot.pinned {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
            }
            if let emoji = slot.emoji {
                // Auto-fill is dimmed so pinned slots read as deliberate.
                Text(displayGlyph(emoji))
                    .font(.system(size: 22))
                    .opacity(slot.pinned ? 1 : 0.4)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 38, height: 38)
        .contentShape(Rectangle())
        .onTapGesture { editing = EditingSlot(id: index) }
        .overlay(alignment: .topTrailing) {
            if slot.pinned {
                Button { store.reset(at: index) } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .help("Reset to most-used")
            }
        }
        .help(slotHelp(slot))
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

/// A searchable emoji grid presented as a sheet — used to pin a Quick Access
/// slot. (A real `TextField` here; the in-panel browser's search is driven by
/// the event tap, which Settings doesn't have.)
struct EmojiPickerSheet: View {
    let onPick: (Emoji) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    private let database = EmojiDatabase.shared
    private let columns = Array(repeating: GridItem(.flexible(minimum: 32), spacing: 4), count: 10)

    private var results: [Emoji] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return database.all.sorted { $0.order < $1.order }
        }
        return FuzzyMatcher.search(
            query: trimmed, in: database, usage: [:],
            corpus: .emojiOnly, useFrequencyBoost: false, limit: 120
        )
        .map(\.emoji)
        .filter { database.byHexcode[$0.hexcode] != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pick an emoji").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search emoji", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                if results.isEmpty {
                    Text("No emoji matching “\(query)”")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(results, id: \.hexcode) { emoji in
                            Button {
                                onPick(emoji)
                                dismiss()
                            } label: {
                                Text(displayGlyph(emoji))
                                    .font(.system(size: 24))
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                            .help(":\(emoji.primaryShortcode):")
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(width: 460, height: 460)
    }

    private func displayGlyph(_ emoji: Emoji) -> String {
        emoji.supportsSkinTone ? SkinTone.current.apply(to: emoji.character) : emoji.character
    }
}
