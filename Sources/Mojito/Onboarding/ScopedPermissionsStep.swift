import SwiftUI

/// Permissions step for systems with scoped grants (macOS 27.3+). The system
/// no longer shows a dialog when an app asks, so this walks through adding
/// the app by hand in System Settings.
struct ScopedPermissionsStep: View {
    let control: ControlAccess
    let inputMonitoringGranted: Bool
    let openControlSettings: () -> Void
    let openInputMonitoringSettings: () -> Void

    @State private var showPrivacyDetails = false
    @State private var relaunching = false

    private var controlDone: Bool { control == .full }
    private var name: String { AppInfo.displayName }

    var body: some View {
        VStack(spacing: 16) {
            // The notice takes the icon's room; the window doesn't grow.
            if control != .limited {
                Image(systemName: "keyboard")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
            }

            VStack(spacing: 6) {
                Text("Let \(name) work with your keyboard")
                    .font(.system(size: 22, weight: .semibold))
                Text("macOS asks you to add \(name) by hand. It takes about a minute.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            VStack(spacing: 6) {
                if control == .limited {
                    LimitedAccessNotice()
                }
                stepRow(
                    number: 1,
                    done: controlDone,
                    title: "Open System & App Protection Override",
                    actionTitle: controlDone ? nil : "Open Settings",
                    action: openControlSettings
                )
                stepRow(number: 2, done: controlDone, title: "Press + and pick \(name)")
                stepRow(
                    number: 3,
                    done: controlDone,
                    title: "Choose Override System Protections",
                    detail: "Not Choose Apps. With that one \(name) can't see what you type."
                )
                stepRow(
                    number: 4,
                    done: inputMonitoringGranted,
                    title: "Turn on \(name) under Input Monitoring",
                    detail: "If \(name) isn't listed, press + and add it.",
                    actionTitle: inputMonitoringGranted ? nil : "Open Settings",
                    action: openInputMonitoringSettings
                )
            }
            .frame(maxWidth: 480)

            if relaunching {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Reopening \(name) to finish…")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
            } else {
                Button("Why does an emoji tool need this?") { showPrivacyDetails = true }
                    .buttonStyle(.link)
                    .font(.system(size: 13))
            }

            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showPrivacyDetails) {
            PrivacyDetailsSheet()
        }
        .onAppear { relaunchIfUnverified() }
        .onChange(of: control) { _, _ in relaunchIfUnverified() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            relaunchIfUnverified()
        }
    }

    /// A grant made while running can't be read back until the next launch.
    /// Wait until the user is back in this window so the relaunch doesn't
    /// pull them out of System Settings mid-step.
    private func relaunchIfUnverified() {
        guard control == .unverified, !relaunching, NSApp.isActive else { return }
        relaunching = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { AppRelauncher.relaunch() }
    }

    private func stepRow(
        number: Int,
        done: Bool,
        title: LocalizedStringKey,
        detail: LocalizedStringKey? = nil,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1))
                }
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 2)

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Shown when the app was added with "Choose Apps": it looks granted to
/// macOS but can't see or type keys.
struct LimitedAccessNotice: View {
    var openSettings: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(AppInfo.displayName) can't see your keyboard yet")
                    .font(.system(size: 13, weight: .medium))
                Text("It was added with Choose Apps. Remove \(AppInfo.displayName) from the list, add it again, and choose Override System Protections.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let openSettings {
                Button("Open Settings", action: openSettings)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
