import SwiftUI

/// A reusable trigger editor embedded inline in the feature sections of
/// Settings ▸ General. Renders one of two states, right-aligned:
///   - a native-looking pop-up `Menu` of preset triggers (+ "Custom…", and for
///     symbols "Same as emoji") when the mode is on a preset, with taken
///     presets grayed out; or
///   - a keyboard-shortcut-recorder-style pill (editable monospaced field +
///     dimmed noun + ✗) when the mode is on a custom trigger.
/// The binding edits a mode's `open` string (and, for symbols, the shared
/// `sameAsEmoji` flag); edits flow back to the caller, which persists the
/// whole `TriggerConfig` via `TriggerConfigStore`.
struct TriggerPicker: View {
    /// The mode this picker edits — drives the preview shape and validator row.
    let mode: TriggerMode
    @Binding var open: String
    let diagnostic: TriggerDiagnostic?
    /// Open strings already claimed by the other active triggers — grayed out
    /// in the menu so a preset pick can never collide. This mode's own open is
    /// never in here.
    let takenOpens: Set<String>
    /// The preset to restore to when the pill's ✗ is tapped.
    let defaultOpen: String
    /// Symbols only: the shared "blend into emoji" flag. `nil` for emoji/gif.
    var sameAsEmoji: Binding<Bool>?

    /// Preset vocabulary, shared across modes.
    private static let presets: [String] = [":", "::", ":::", ";", "/", "!", "#"]

    private var followsEmoji: Bool { sameAsEmoji?.wrappedValue ?? false }

    /// On a preset (and not "Same as emoji") → menu; otherwise the pill.
    private var isCustom: Bool { !followsEmoji && !Self.presets.contains(open) }

    /// Human name for a preset glyph (`:` → "Colon") so options read
    /// `: Colon` rather than a bare, ambiguous punctuation mark.
    private func presetName(_ preset: String) -> String {
        switch preset {
        case ":":   return String(localized: "Colon")
        case "::":  return String(localized: "Double colon")
        case ":::": return String(localized: "Triple colon")
        case ";":   return String(localized: "Semicolon")
        case "/":   return String(localized: "Slash")
        case "!":   return String(localized: "Exclamation mark")
        case "#":   return String(localized: "Hash")
        default:    return ""
        }
    }

    private func presetLabel(_ preset: String) -> String {
        let name = presetName(preset)
        return name.isEmpty ? preset : "\(preset) \(name)"
    }

    /// What the menu's button shows for the current selection.
    private var menuLabel: String {
        followsEmoji ? String(localized: "Same as emoji") : presetLabel(open)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("Trigger")
            Spacer(minLength: 0)

            if let diagnostic {
                DiagnosticBadge(diagnostic: diagnostic)
            }

            if isCustom {
                CustomTriggerPill(text: $open) {
                    // ✗ → back to the preset default (pill disappears). Symbols
                    // keeps follow=false (it's a scoped trigger again).
                    open = defaultOpen
                }
            } else {
                triggerMenu
            }
        }
        .padding(.vertical, 1)

        if let diagnostic {
            Text(diagnostic.message)
                .font(.callout)
                .foregroundStyle(diagnostic.severity == .note ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A `Menu` (not `Picker`) so individual preset rows can be `.disabled()`.
    /// Styled to read as a native pop-up button.
    private var triggerMenu: some View {
        Menu {
            if sameAsEmoji != nil {
                Button(String(localized: "Same as emoji")) {
                    sameAsEmoji?.wrappedValue = true
                }
                Divider()
            }
            ForEach(Self.presets, id: \.self) { preset in
                Button {
                    sameAsEmoji?.wrappedValue = false
                    open = preset
                } label: {
                    Text(verbatim: presetLabel(preset))
                }
                .disabled(preset != open && takenOpens.contains(preset))
            }
            Divider()
            Button(String(localized: "Custom…")) {
                sameAsEmoji?.wrappedValue = false
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

/// A keyboard-shortcut-recorder-style pill for a custom trigger: an editable
/// field plus a ✗ to reset to the default preset. The literal string IS the
/// trigger, so we trim nothing — but newlines would wreck the field, so
/// they're stripped.
private struct CustomTriggerPill: View {
    @Binding var text: String
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // An editable TextField ignores `.fixedSize()` and expands to fill,
            // so bound it explicitly — triggers are 1–3 chars.
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                .onChange(of: text) { _, newValue in
                    let stripped = newValue.replacingOccurrences(of: "\n", with: "")
                        .replacingOccurrences(of: "\r", with: "")
                    if stripped != newValue { text = stripped }
                }
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .fixedSize()
    }
}

/// Inline severity badge: red error / orange warning triangle, secondary
/// info circle for a note. The message rides along as a tooltip.
struct DiagnosticBadge: View {
    let diagnostic: TriggerDiagnostic

    private var color: Color {
        switch diagnostic.severity {
        case .error:   return .red
        case .warning: return .orange
        case .note:    return .secondary
        }
    }

    private var symbol: String {
        diagnostic.severity == .note ? "info.circle" : "exclamationmark.triangle.fill"
    }

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .help(diagnostic.message)
    }
}
