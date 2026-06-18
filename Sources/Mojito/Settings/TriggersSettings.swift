import SwiftUI

/// Settings ▸ Triggers — lets the user retune the strings that fire each of
/// the four fixed modes (emoji / symbols / GIF / quick access). Edits persist
/// immediately via `TriggerConfigStore`, whose write posts a UserDefaults
/// change the Engine observes, so the live state machine picks up new triggers
/// without a relaunch. Inline diagnostics (`TriggerValidator`) flag collisions,
/// risky letters, and unreachable triggers.
struct TriggersSettingsView: View {
    @State private var config: TriggerConfig = TriggerConfigStore.load()

    private var diagnostics: [TriggerMode: TriggerDiagnostic] {
        TriggerValidator.diagnostics(for: config)
    }

    var body: some View {
        Form {
            Section {
                TriggerRow(
                    title: "Emoji",
                    open: $config.emoji.open,
                    close: closeBinding(\.emoji),
                    enabled: nil,
                    diagnostic: diagnostics[.emoji])
            }

            Section {
                TriggerRow(
                    title: "Symbols",
                    open: $config.symbols.open,
                    close: closeBinding(\.symbols),
                    enabled: $config.symbols.enabled,
                    diagnostic: diagnostics[.symbols])
            }

            Section {
                TriggerRow(
                    title: "GIF",
                    open: $config.gif.open,
                    close: nil,
                    enabled: $config.gif.enabled,
                    diagnostic: diagnostics[.gif])
            }

            Section {
                TriggerRow(
                    title: "Quick access",
                    open: $config.quickAccess.open,
                    close: nil,
                    enabled: $config.quickAccess.enabled,
                    diagnostic: diagnostics[.quickAccess])
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset to defaults") {
                        config = .default
                    }
                }
            } footer: {
                Text("Triggers are the characters you type to fire emoji, symbols, GIF search, and quick access. Defaults are punctuation; you can use anything, but watch the warnings — letters and spaces tend to misfire.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onChange(of: config) { _, newValue in
            TriggerConfigStore.save(newValue)
        }
    }

    /// The model's `close` is `String?`; the field binds to a non-optional
    /// `String` (empty == no close), so reflect that here.
    private func closeBinding(_ key: WritableKeyPath<TriggerConfig, Trigger>) -> Binding<String> {
        Binding(
            get: { config[keyPath: key].close ?? "" },
            set: { config[keyPath: key].close = $0.isEmpty ? nil : $0 }
        )
    }
}

/// One mode's row: a labeled open field, an optional close field, an optional
/// enable toggle, and an inline diagnostic badge.
private struct TriggerRow: View {
    let title: LocalizedStringKey
    @Binding var open: String
    let close: Binding<String>?
    let enabled: Binding<Bool>?
    let diagnostic: TriggerDiagnostic?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(title)
                    .frame(width: 110, alignment: .leading)

                LabeledField(label: "open", text: $open)
                if let close {
                    LabeledField(label: "close", text: close)
                }

                if let diagnostic {
                    DiagnosticBadge(diagnostic: diagnostic)
                }

                Spacer(minLength: 0)

                if let enabled {
                    Toggle("", isOn: enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            if let diagnostic {
                Text(diagnostic.message)
                    .font(.callout)
                    .foregroundStyle(diagnostic.severity == .note ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 122)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A small caption above a narrow monospaced text field. The literal string
/// IS the trigger, so we trim nothing — but newlines are never useful and
/// would wreck the field, so they're stripped.
private struct LabeledField: View {
    let label: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
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
}

private struct DiagnosticBadge: View {
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
