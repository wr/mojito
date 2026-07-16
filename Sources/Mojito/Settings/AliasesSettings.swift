import SwiftUI

/// Settings ▸ Aliases. Lets the user add their own `:word:` → emoji or symbol
/// mappings on top of the baked corpus (W-453). Editing writes through
/// `AliasStore`, which re-merges the emoji index live.
struct AliasesSettingsView: View {
    @StateObject private var store = AliasStore.shared
    private let database = EmojiDatabase.shared

    @State private var showAdd = false
    @State private var selected: String?
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AliasCard(
                    aliases: store.aliases,
                    glyph: glyph(for:),
                    selected: $selected,
                    onAdd: { showAdd = true },
                    onRemove: removeSelected
                )

                if store.aliases.count > 1 {
                    HStack {
                        Spacer()
                        Button("Clear all aliases") { confirmClear = true }
                            .confirmationDialog(
                                "Remove all aliases?",
                                isPresented: $confirmClear,
                                titleVisibility: .visible
                            ) {
                                Button("Remove all", role: .destructive) {
                                    store.removeAll()
                                    selected = nil
                                }
                                Button("Cancel", role: .cancel) {}
                            }
                    }
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showAdd) {
            AddAliasSheet(store: store) { showAdd = false }
        }
    }

    private func glyph(for alias: CustomAlias) -> String? {
        database.byHexcode[alias.hexcode]?.tonedGlyph
            ?? SymbolsDatabase.byHexcode[alias.hexcode]?.tonedGlyph
    }

    private func removeSelected() {
        guard let selected else { return }
        store.remove(alias: selected)
        self.selected = nil
    }
}

// MARK: - Alias list card

/// Boxed list matching the Exclusions cards: content-sized, hairline border,
/// a `+`/`−` footer.
private struct AliasCard: View {
    let aliases: [CustomAlias]
    let glyph: (CustomAlias) -> String?
    @Binding var selected: String?
    let onAdd: () -> Void
    let onRemove: () -> Void

    private let cornerRadius: CGFloat = 10
    private let innerSeparator = Color.primary.opacity(0.08)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            innerSeparator.frame(height: 0.5)
            if aliases.isEmpty {
                emptyState
            } else {
                rows
            }
            innerSeparator.frame(height: 0.5)
            footer
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private var header: some View {
        Text("Type these aliases to insert their emoji or symbol. They work alongside the built-in shortcodes.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    private var emptyState: some View {
        Text("No aliases yet. Add one to type `:yourword:` for any emoji or symbol.")
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(aliases.enumerated()), id: \.element.id) { idx, alias in
                row(alias)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(selected == alias.id ? Color.accentColor : Color.clear)
                    .foregroundStyle(selected == alias.id ? Color.white : Color.primary)
                    .onTapGesture { selected = alias.id }

                if idx < aliases.count - 1 {
                    innerSeparator.frame(height: 0.5).padding(.leading, 50)
                }
            }
        }
    }

    private func row(_ alias: CustomAlias) -> some View {
        HStack(spacing: 10) {
            Text(glyph(alias) ?? "❓")
                .font(.system(size: 22))
                .frame(width: 28, height: 28)
            Text(":\(alias.alias):")
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Divider()

            Button(action: onRemove) {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(selected == nil)

            Spacer()
        }
        .background(Color.primary.opacity(0.04))
    }
}

// MARK: - Add sheet

/// Type the alias, pick its emoji or symbol, add. The target is chosen with the
/// same browser used everywhere else, nested in a sheet.
private struct AddAliasSheet: View {
    @ObservedObject var store: AliasStore
    let onClose: () -> Void

    @State private var text = ""
    @State private var pickedHexcode: String?
    @State private var pickedGlyph: String?
    @State private var showPicker = false

    private var normalized: String? { AliasStore.normalize(text) }
    private var canAdd: Bool { normalized != nil && pickedHexcode != nil }
    private var isDuplicate: Bool {
        guard let normalized else { return false }
        return store.contains(alias: normalized)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add alias").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Your alias, e.g. check", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if canAdd { add() } }
                if isDuplicate {
                    Text(":\(normalized ?? ""): already exists — adding updates its target.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Text(pickedGlyph ?? "🙂")
                            .font(.system(size: 24))
                            .opacity(pickedGlyph == nil ? 0.35 : 1)
                        Text(pickedGlyph == nil ? "Choose emoji or symbol…" : "Change")
                    }
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 360)
        .sheet(isPresented: $showPicker) {
            EmojiPickerSheet { emoji in
                pickedHexcode = emoji.hexcode
                pickedGlyph = emoji.tonedGlyph
            }
        }
    }

    private func add() {
        guard let normalized, let hex = pickedHexcode else { return }
        store.add(alias: normalized, hexcode: hex)
        onClose()
    }
}

/// The shared emoji browser hosted in a sheet, returning the chosen emoji or
/// symbol. Symbols are forced in (`includeSymbols`) so they're pickable as
/// alias targets regardless of the global Symbols toggle.
private struct EmojiPickerSheet: View {
    let onPick: (Emoji) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = EmojiBrowserViewModel(
        database: .shared, quickAccess: .shared, includeSymbols: true
    )

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pick an emoji or symbol").font(.headline)
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
