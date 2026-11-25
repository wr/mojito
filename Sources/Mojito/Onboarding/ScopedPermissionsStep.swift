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
    @State private var openedControlSettings = false

    private var name: String { AppInfo.displayName }
    /// macOS only reports the end states, so the steps tick in groups: the
    /// app reads as trusted once it's in the list, and as full once the
    /// override is allowed.
    private var added: Bool { control != .none }
    private var overridden: Bool { control == .full }

    private var privacyIcon: Image { SettingsGlyph.image("hand.raised.fill", fill: .systemBlue) }
    private var overrideIcon: Image { SettingsGlyph.image("square.2.layers.3d.fill", fill: .systemBlue) }
    private var inputIcon: Image { SettingsGlyph.image("keyboard.fill", fill: .systemGray) }
    private var plusIcon: Image { SettingsGlyph.image("plus", fill: .quaternaryLabelColor, glyph: .labelColor) }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("Let \(name) work with your keyboard")
                    .font(.system(size: 22, weight: .semibold))
                Text("macOS asks you to add \(name) by hand. It takes about a minute.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                box {
                    step(
                        1,
                        done: added || openedControlSettings,
                        title: "Open \(privacyIcon) **Privacy & Security** → \(overrideIcon) **System & App Protection Override**",
                        actionTitle: overridden ? nil : "Open Settings",
                        action: {
                            openedControlSettings = true
                            openControlSettings()
                        }
                    )
                    step(
                        2,
                        done: added,
                        title: "Click the \(plusIcon) button at the bottom of the list and choose **\(name)** in the file browser"
                    )
                    if control == .limited {
                        step(
                            3,
                            done: false,
                            warning: true,
                            title: "\(name) was added with **Choose Apps**, so it can't see your keyboard",
                            detail: "Remove \(name) from the list, add it again, and click **Override System Protections**."
                        )
                    } else {
                        step(
                            3,
                            done: overridden,
                            title: "Click the **Override System Protections** button",
                            detail: "Don't click **Choose Apps** — \(name) will not work with app-level permissions."
                        )
                    }
                    step(
                        4,
                        done: overridden,
                        title: "Click all of the red **OK** buttons to enable the red **Allow System & App Protection Override** button, and click it",
                        detail: "Your Mac will ask for your password or Touch ID to confirm."
                    )
                }
                box {
                    step(
                        5,
                        done: inputMonitoringGranted,
                        title: "Turn on **\(name)** under \(privacyIcon) **Privacy & Security** → \(inputIcon) **Input Monitoring**",
                        actionTitle: inputMonitoringGranted ? nil : "Open Settings",
                        action: openInputMonitoringSettings
                    )
                }
            }

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

    private func box<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func step(
        _ number: Int,
        done: Bool,
        warning: Bool = false,
        title: LocalizedStringKey,
        detail: LocalizedStringKey? = nil,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, .green)
                } else if warning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.orange)
                } else {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1))
                }
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
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
    }
}

/// Small rounded-square icons in the style of System Settings' sidebar, as
/// images so they can sit inline in a line of text.
enum SettingsGlyph {
    static func image(_ symbol: String, fill: NSColor, glyph: NSColor = .white) -> Image {
        let side: CGFloat = 15
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5).fill()
            let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
                .applying(.init(paletteColors: [glyph]))
            if let mark = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let size = mark.size
                mark.draw(in: NSRect(
                    x: (side - size.width) / 2,
                    y: (side - size.height) / 2,
                    width: size.width,
                    height: size.height
                ))
            }
            return true
        }
        return Image(nsImage: image)
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
