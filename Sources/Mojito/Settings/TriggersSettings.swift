import SwiftUI

/// A reusable trigger editor embedded inline in the feature sections of
/// Settings ▸ General. A labeled Picker over the shared preset vocabulary, an
/// optional narrow Custom field, a live preview, and a `TriggerValidator`
/// badge. The Picker binds to a mode's `open` string; edits flow back to the
/// caller, which persists the whole `TriggerConfig` via `TriggerConfigStore`.
struct TriggerPicker: View {
    /// The mode this picker edits — drives the preview shape and validator row.
    let mode: TriggerMode
    @Binding var open: String
    let diagnostic: TriggerDiagnostic?

    /// Preset vocabulary, shared across modes. `nil` sentinel = "Custom…".
    private static let presets: [String] = [":", "::", ":::", ";", "/", "!", "#"]
    private static let customTag = "\u{0}custom"

    /// `open` matches a preset → that preset's tag; otherwise the Custom tag.
    private var selectionTag: String {
        Self.presets.contains(open) ? open : Self.customTag
    }

    private var isCustom: Bool { selectionTag == Self.customTag }

    /// The mode's own name, used as the sample word in each option so a row
    /// reads as what it does (`:emoji`, `::symbol`, `:::gif`) instead of a bare,
    /// ambiguous punctuation glyph.
    private var noun: String {
        switch mode {
        case .emoji:       return String(localized: "emoji")
        case .symbols:     return String(localized: "symbol")
        case .gif:         return String(localized: "gif")
        case .quickAccess: return ""
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("Trigger")
            Spacer(minLength: 0)

            if isCustom {
                CustomTriggerField(text: $open)
            }
            if let diagnostic {
                DiagnosticBadge(diagnostic: diagnostic)
            }

            // Right-aligned select; each row shows the trigger applied to the
            // mode's name (`:::gif`) so the menu is self-describing.
            Picker("", selection: Binding(
                get: { selectionTag },
                set: { newTag in
                    if newTag == Self.customTag {
                        // Switching into Custom starts from a clean field.
                        if Self.presets.contains(open) { open = "" }
                    } else {
                        open = newTag
                    }
                }
            )) {
                ForEach(Self.presets, id: \.self) { preset in
                    Text(verbatim: preset + noun)
                        .font(.system(.body, design: .monospaced))
                        .tag(preset)
                }
                Text("Custom…").tag(Self.customTag)
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.vertical, 1)

        // In Custom the menu just says "Custom…", so echo what it produces.
        if isCustom, !open.isEmpty {
            HStack {
                Spacer()
                Text(verbatim: open + noun)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }

        if let diagnostic {
            Text(diagnostic.message)
                .font(.callout)
                .foregroundStyle(diagnostic.severity == .note ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A narrow monospaced field for a custom trigger. The literal string IS the
/// trigger, so we trim nothing — but newlines would wreck the field, so
/// they're stripped.
private struct CustomTriggerField: View {
    @Binding var text: String

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .frame(width: 70)
            .onChange(of: text) { _, newValue in
                let stripped = newValue.replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "\r", with: "")
                if stripped != newValue { text = stripped }
            }
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
