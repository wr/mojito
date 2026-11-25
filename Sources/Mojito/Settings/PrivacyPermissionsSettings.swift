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
                if ControlAccess.systemHasScopedGrants {
                    if permissions.control == .limited {
                        LimitedAccessNotice(openSettings: permissions.openAccessibilitySettings)
                            .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                    }
                    permissionRow(
                        title: "System & App Protection Override",
                        detail: "Watches for triggers, finds your text cursor and types the emoji.",
                        granted: permissions.control.isUsable,
                        actionTitle: "Open Settings",
                        onAction: permissions.openAccessibilitySettings
                    )
                } else {
                    permissionRow(
                        title: "Accessibility",
                        detail: "Anchors the picker next to your text cursor.",
                        granted: permissions.accessibility,
                        onAction: handleAccessibility
                    )
                }
                permissionRow(
                    title: "Input Monitoring",
                    detail: "Watches keystrokes for the `:` trigger.",
                    granted: permissions.inputMonitoring,
                    actionTitle: ControlAccess.systemHasScopedGrants ? "Open Settings" : "Allow",
                    onAction: handleInputMonitoring
                )
            }

            Section("Privacy") {
                PrivacyDetailsRows()
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Rows

    private func permissionRow(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        granted: Bool,
        actionTitle: LocalizedStringKey = "Allow",
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
                Button(actionTitle, action: onAction)
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
        if imPromptFired || ControlAccess.systemHasScopedGrants {
            // Scoped systems show no dialog; asking can still add the row.
            if !imPromptFired { _ = permissions.promptInputMonitoring(); imPromptFired = true }
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
    var body: some View {
        if ControlAccess.systemHasScopedGrants {
            privacyRow(
                icon: "exclamationmark.shield",
                title: "Why macOS warns you",
                detail: "\(AppInfo.displayName) only watches for triggers and types the emoji. A blue menu bar icon lists it while it runs."
            )
        }
        privacyRow(
            icon: "keyboard",
            title: "Keystrokes aren't logged",
            detail: "Used to detect `:` triggers. Nothing else."
        )
        privacyRow(
            icon: "eye.slash",
            title: "You are anonymous",
            detail: "Statistics and GIF searches sent to KLIPY are never linked to you, and no personally-identifiable data is stored or sent anywhere."
        )
        privacyRow(
            icon: "dollarsign.circle",
            title: "You are not the product",
            detail: "Funded by donations, not ads, tracking, or subscriptions."
        ) {
            Button("Donate") {
                NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/wellsworkshop")!)
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
    @AppStorage(PrefsKey.telemetryEnabled) private var telemetryEnabled: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: OnboardingHeader.formSpacing) {
                OnboardingHeader(
                    systemImage: "hand.raised.fill",
                    title: "Privacy",
                    subtitle: "\(AppInfo.displayName) is built to respect your privacy. Here's how."
                )
                .padding(.top, 28)

                Form {
                    PrivacyDetailsRows()

                    Toggle(isOn: $telemetryEnabled) {
                        HStack(spacing: 4) {
                            Text("Share anonymous usage stats")
                            StatsHelpButton()
                        }
                    }
                    .toggleStyle(.switch)
                }
                .formStyle(.grouped)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 500, height: ControlAccess.systemHasScopedGrants ? 620 : 560)
        .onAppear {
            // Seeing the privacy sheet (with the stats toggle + anonymity
            // explanation) satisfies the one-time stats-consent gate.
            UserDefaults.standard.set(true, forKey: PrefsKey.telemetryConsentSeen)
        }
    }
}
