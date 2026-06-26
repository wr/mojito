import SwiftUI
import AppKit

/// A reusable trigger editor embedded inline in the feature sections of
/// Settings ▸ General. Renders one of two states, right-aligned:
///   - a native-looking pop-up `Menu` of preset triggers (each shown as its
///     glyph — `:`, `;`, and `;?` for quick access — plus "Custom…", and for
///     symbols "Same as emoji"), with taken presets grayed out; or
///   - a recorder-style capsule (editable field + ✗) when on a custom trigger.
/// The binding edits a mode's `open` string (and, for symbols, the shared
/// `sameAsEmoji` flag); edits flow back to the caller, which persists the
/// whole `TriggerConfig` via `TriggerConfigStore`.
struct TriggerPicker: View {
    /// Labels the row ("Emoji trigger" / …) — the picker is otherwise identical.
    let mode: TriggerMode
    @Binding var open: String
    /// Open strings already claimed by the other active triggers — grayed out
    /// in the menu so a preset pick can never collide. This mode's own open is
    /// never in here.
    let takenOpens: Set<String>
    /// The preset to restore to when the pill's ✗ is tapped.
    let defaultOpen: String
    /// Symbols / quick access: the shared "follow the emoji trigger" flag.
    /// `nil` for emoji/gif (no follow option).
    var sameAsEmoji: Binding<Bool>?
    /// Menu text for the follow option. nil → "Same as emoji" (symbols);
    /// quick access passes the derived `:?` so it reads as the actual trigger.
    var followLabel: String?
    /// When the mode's default *is* "follow emoji" (symbols / quick access),
    /// the pill's ✗ returns to that rather than to a preset open.
    var defaultFollowsEmoji: Bool = false

    /// Whether the custom pill is showing. Explicit state (not derived from
    /// `open`) so typing a value that happens to match a preset (`:`, `;`, …)
    /// doesn't collapse the pill back to the menu mid-edit. Seeded on appear
    /// from a persisted custom open.
    @State private var customMode = false

    /// Preset vocabulary, shared across modes.
    private static let presets: [String] = [":", "::", ":::", ";", "/", "!", "#"]

    private var followsEmoji: Bool { sameAsEmoji?.wrappedValue ?? false }

    /// Show the pill while editing a custom trigger; otherwise the menu.
    private var showPill: Bool { !followsEmoji && customMode }

    /// The row label, per feature (mirrors "Emoji Browser shortcut").
    private var rowLabel: String {
        switch mode {
        case .emoji:       return String(localized: "Emoji trigger")
        case .symbols:     return String(localized: "Symbol trigger")
        case .gif:         return String(localized: "GIF trigger")
        case .quickAccess: return String(localized: "Quick Access trigger")
        }
    }

    /// The follow-option text (and the menu's label while following).
    private var resolvedFollowLabel: String {
        followLabel ?? String(localized: "Same as emoji")
    }

    private var isQuickAccess: Bool { mode == .quickAccess }

    /// The open a preset maps to. Quick Access always carries the `?` marker
    /// (`#` → `#?`), matching the follow-emoji default (`:?`).
    private func presetOpen(_ preset: String) -> String {
        isQuickAccess ? preset + "?" : preset
    }

    /// The base preset behind an open (strips the Quick Access `?`).
    private func baseOf(_ open: String) -> String {
        isQuickAccess && open.hasSuffix("?") ? String(open.dropLast()) : open
    }

    /// What the menu's button shows for the current selection — the glyph itself.
    private var menuLabel: String {
        followsEmoji ? resolvedFollowLabel : open
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(rowLabel)
            Spacer(minLength: 0)
            if showPill {
                CustomTriggerPill(text: $open) {
                    // ✗ → the mode's default (menu returns): "follow emoji" for
                    // symbols/quick access, else the preset open.
                    customMode = false
                    if defaultFollowsEmoji {
                        sameAsEmoji?.wrappedValue = true
                    } else {
                        open = defaultOpen
                    }
                }
            } else {
                triggerMenu
            }
        }
        .padding(.vertical, 1)
        // Hold a constant row height across both states so the row doesn't
        // jump when toggling between the menu and the (taller) custom pill.
        .frame(minHeight: 26)
        // Seed the pill from a persisted custom trigger (a non-preset open).
        .onAppear { customMode = !followsEmoji && !Self.presets.contains(baseOf(open)) }
    }

    /// Presets shown in the menu. For Quick Access, drop the one that would
    /// render identically to the "follow emoji" option (`:` → `:?`), so the
    /// menu doesn't show a duplicate of the follow row.
    private var menuPresets: [String] {
        guard isQuickAccess, sameAsEmoji != nil else { return Self.presets }
        return Self.presets.filter { presetOpen($0) != resolvedFollowLabel }
    }

    /// A `Menu` (not `Picker`) so individual preset rows can be `.disabled()`.
    /// Styled to read as a native pop-up button.
    private var triggerMenu: some View {
        Menu {
            if sameAsEmoji != nil {
                Button(resolvedFollowLabel) {
                    customMode = false
                    sameAsEmoji?.wrappedValue = true
                }
                Divider()
            }
            ForEach(menuPresets, id: \.self) { preset in
                Button {
                    customMode = false
                    sameAsEmoji?.wrappedValue = false
                    open = presetOpen(preset)
                } label: {
                    Text(verbatim: presetOpen(preset))
                }
                // Collision is on the base char — `#?` can't coexist with a `#`
                // trigger — so the taken check stays keyed on the bare preset.
                .disabled(presetOpen(preset) != open && takenOpens.contains(preset))
            }
            Divider()
            Button(String(localized: "Custom…")) {
                sameAsEmoji?.wrappedValue = false
                customMode = true
                // Clear so the pill appears empty, ready to type into.
                open = ""
            }
        } label: {
            Text(verbatim: menuLabel)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .fixedSize()
    }
}

/// A System-Settings-style section header row: a colored squircle icon, a
/// title + subtitle, and (for the optional-feature sections) a large enable
/// switch on the trailing edge. The first row of each feature section.
struct SettingsSectionHeader: View {
    let systemImage: String
    let tint: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    /// Per-icon point size — some glyphs read optically lighter/smaller than
    /// others, so they need their own value to look balanced.
    var iconSize: CGFloat = 13
    /// Per-icon vertical nudge to correct a glyph's optical centering.
    var iconOffsetY: CGFloat = 0
    /// nil for always-on features (emoji); a binding shows a large switch.
    var isOn: Binding<Bool>?

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(y: iconOffsetY)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let isOn {
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    // A touch larger than default (there's no size between
                    // `.regular` and the oversized `.large`).
                    .scaleEffect(1.2, anchor: .trailing)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A custom-trigger field styled to match the global-shortcut recorder box: a
/// fixed-size rounded field (white fill, hairline border, accent border while
/// editing) with a trailing clear (✗) button. Unlike the recorder it takes free
/// text — the literal string IS the trigger, so we trim nothing, but newlines
/// are stripped and the length is capped (a trigger is a short delimiter).
private struct CustomTriggerPill: View {
    @Binding var text: String
    let onClear: () -> Void

    @State private var isEditing = false
    private static let maxLength = 5

    var body: some View {
        HStack(spacing: 4) {
            TriggerTextField(text: $text, maxLength: Self.maxLength) { isEditing = $0 }
                .frame(maxWidth: .infinity)
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(width: 124, height: 24)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(isEditing ? Color(nsColor: .controlAccentColor) : Color(nsColor: .separatorColor),
                          lineWidth: isEditing ? 2 : 1))
    }
}

/// A borderless, centered, single-line editable field. SwiftUI's TextField
/// inherits a Form's right text alignment, so this drops to NSTextField to
/// control alignment and report focus. Strips newlines and caps the length.
private struct TriggerTextField: NSViewRepresentable {
    @Binding var text: String
    let maxLength: Int
    var onFocusChange: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Auto-focus when the field first appears empty — i.e. the user just
        // chose "Custom…" — so they can type immediately. A pre-existing custom
        // trigger (non-empty on open) is left unfocused.
        if text.isEmpty {
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: TriggerTextField
        init(_ parent: TriggerTextField) { self.parent = parent }

        func controlTextDidBeginEditing(_ obj: Notification) { parent.onFocusChange?(true) }
        func controlTextDidEndEditing(_ obj: Notification) { parent.onFocusChange?(false) }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            var v = field.stringValue
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
            if v.count > parent.maxLength { v = String(v.prefix(parent.maxLength)) }
            if v != field.stringValue { field.stringValue = v }
            parent.text = v
        }
    }
}
