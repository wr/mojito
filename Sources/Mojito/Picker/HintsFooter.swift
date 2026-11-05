import SwiftUI

/// One keyboard hint for a picker footer: one or more keycap glyphs plus an
/// optional localized label.
struct KeyHint: Identifiable {
    let keys: [String]
    let label: LocalizedStringKey?

    init(_ key: String, _ label: LocalizedStringKey? = nil) {
        self.init(keys: [key], label)
    }

    /// Several keys sharing one label (`↵` `1–9` insert).
    init(keys: [String], _ label: LocalizedStringKey? = nil) {
        self.keys = keys
        self.label = label
    }

    var id: String { keys.joined(separator: " ") }
}

/// A single keycap + label pair, styled like the macOS menu hint text.
struct KeyHintLabel: View {
    let hint: KeyHint

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(hint.keys, id: \.self) { key in
                    Text(verbatim: key)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
            if let label = hint.label {
                Text(label)
            }
        }
        .fixedSize()
    }
}

/// Keyboard-hint footer row shared by the floating pickers. Trailing content
/// (e.g. attribution) sits after the spacer.
struct HintsFooter<Trailing: View>: View {
    let hints: [KeyHint]
    let trailing: Trailing

    init(_ hints: [KeyHint], @ViewBuilder trailing: () -> Trailing) {
        self.hints = hints
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(hints) { hint in
                KeyHintLabel(hint: hint)
            }
            Spacer(minLength: 6)
            trailing
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

extension HintsFooter where Trailing == EmptyView {
    init(_ hints: [KeyHint]) {
        self.init(hints) { EmptyView() }
    }
}
