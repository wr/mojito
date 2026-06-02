import SwiftUI

struct PrivacyPermissionsSettingsView: View {
    @EnvironmentObject private var permissions: PermissionsCoordinator

    @State private var axPromptFired = false
    @State private var imPromptFired = false

    var body: some View {
        Form {
            // Permissions first — the actionable rows. Privacy
            // explanation below since it's read-once.
            Section("Permissions") {
                permissionRow(
                    title: "Accessibility",
                    detail: "Anchors the picker next to your text cursor.",
                    granted: permissions.accessibility,
                    onAction: handleAccessibility
                )
                permissionRow(
                    title: "Input Monitoring",
                    detail: "Watches keystrokes for the `:` trigger.",
                    granted: permissions.inputMonitoring,
                    onAction: handleInputMonitoring
                )
            }

            Section("Privacy") {
                PrivacyDetailsRows()
                HStack {
                    Text("Danger zone")
                    Spacer()
                    ClearStatsButton()
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Rows

    private func permissionRow(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        granted: Bool,
        onAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
            } else {
                Button("Allow", action: onAction)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func handleAccessibility() {
        if axPromptFired {
            permissions.openAccessibilitySettings()
        } else {
            _ = permissions.promptAccessibility()
            axPromptFired = true
        }
    }

    private func handleInputMonitoring() {
        if imPromptFired {
            permissions.openInputMonitoringSettings()
        } else {
            _ = permissions.promptInputMonitoring()
            imPromptFired = true
        }
    }
}

// MARK: - Privacy details

/// Shared between Settings → Privacy and the onboarding "Privacy details…" sheet.
struct PrivacyDetailsRows: View {
    @AppStorage(PrefsKey.telemetryEnabled) private var telemetryEnabled = true

    var body: some View {
        Group {
            privacyRow(
                icon: "keyboard",
                title: "Keystrokes aren't logged",
                detail: "Used to detect `:` triggers. Nothing else."
            )
            privacyRow(
                icon: "internaldrive",
                title: "Your data stays on this Mac",
                detail: "Usage counts, settings, and your exclusion list live only on this Mac.\n\nException: GIF search sends your query to Giphy when you use it."
            )
            privacyRow(
                icon: "chart.bar.xaxis",
                title: "Share anonymous usage stats",
                detail: "Once a day: which emoji are popular, which features you use, and your macOS version. No identifiers, no IP address, and nothing you type."
            ) {
                Toggle("", isOn: $telemetryEnabled).labelsHidden()
            }
            privacyRow(
                icon: "checklist",
                title: "Everything we collect is public",
                detail: "The full dataset is published, live — the page is the documentation."
            ) {
                Button("View stats") {
                    NSWorkspace.shared.open(URL(string: "https://mojito.wells.ee/stats")!)
                }
            }
            privacyRow(
                icon: "dollarsign.circle",
                title: "Funded by donations",
                detail: "No ads, tracking, or subscriptions."
            ) {
                Button("Donate") {
                    NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/wellsriley")!)
                }
            }
            privacyRow(
                icon: "chevron.left.forwardslash.chevron.right",
                title: "Open source and auditable",
                detail: "All the code is on GitHub. Read it, build it, fork it."
            ) {
                Button("View source") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/wr/mojito")!)
                }
            }
        }
        .onAppear {
            // Seeing this disclosure (Settings ▸ Privacy or the onboarding
            // sheet) satisfies the consent gate, so the one-time launch notice
            // won't double up for users who poke around Settings first.
            UserDefaults.standard.set(true, forKey: PrefsKey.telemetryConsentSeen)
        }
    }

    private func privacyRow(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        privacyRow(icon: icon, title: title, detail: detail) { EmptyView() }
    }

    private func privacyRow<Accessory: View>(
        icon: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            accessory()
        }
        .padding(.vertical, 2)
    }
}

/// Surfaced by the onboarding permissions step.
struct PrivacyDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .padding(.top, 24)

                VStack(spacing: 6) {
                    Text("Privacy")
                        .font(.system(size: 22, weight: .semibold))
                    Text("\(AppInfo.displayName) is built to respect your privacy. Here's how.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                Form {
                    PrivacyDetailsRows()
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 500, height: 520)
    }
}
