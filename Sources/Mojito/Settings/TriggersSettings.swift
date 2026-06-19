import SwiftUI

/// A reusable trigger editor embedded inline in the feature sections of
/// Settings ▸ General. Renders one of two states, right-aligned:
///   - a native-looking pop-up `Menu` of preset triggers (each shown as
///     `: Colon`, plus "Custom…", and for symbols "Same as emoji"), with
///     taken presets grayed out; or
///   - a recorder-style capsule (editable field + ✗) when on a custom trigger.
/// The binding edits a mode's `open` string (and, for symbols, the shared
/// `sameAsEmoji` flag); edits flow back to the caller, which persists the
/// whole `TriggerConfig` via `TriggerConfigStore`.
struct TriggerPicker: View {
    @Binding var open: String
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

/// A custom-trigger field styled to match the `KeyboardShortcuts` recorder
/// pill used elsewhere on this page: a fixed-width capsule with centered text
/// and a trailing clear (✗) button. The literal string IS the trigger, so we
/// trim nothing — but newlines are stripped and the length is capped (a
/// trigger is a short delimiter, never prose).
private struct CustomTriggerPill: View {
    @Binding var text: String
    let onClear: () -> Void

    private static let maxLength = 5

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .onChange(of: text) { _, newValue in
                    var v = newValue.replacingOccurrences(of: "\n", with: "")
                        .replacingOccurrences(of: "\r", with: "")
                    if v.count > Self.maxLength { v = String(v.prefix(Self.maxLength)) }
                    if v != newValue { text = v }
                }
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .frame(width: 132, height: 22)
        .background(Capsule().fill(Color(nsColor: .textBackgroundColor)))
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}
