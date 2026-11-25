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

    private var privacyIcon: Text { SettingsGlyph.inline("hand.raised.fill", fill: .systemBlue) }
    private var overrideIcon: Text { SettingsGlyph.inline("square.2.layers.3d.fill", fill: .systemBlue) }
    private var inputIcon: Text { SettingsGlyph.inline("keyboard.fill", fill: .systemGray) }
    private var plusIcon: Text { SettingsGlyph.inline("plus", fill: .quaternaryLabelColor, glyph: .labelColor) }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 32))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("\(name) needs your permission")
                    .font(.system(size: 22, weight: .semibold))
                Text("The steps below are required to use \(name).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                box(done: overridden) {
                    step(
                        1,
                        done: added || openedControlSettings,
                        title: "Open \(privacyIcon) Privacy & Security → \(overrideIcon) System & App Protection Override",
                        actionTitle: overridden ? nil : "Open Settings",
                        action: {
                            openedControlSettings = true
                            openControlSettings()
                        }
                    )
                    step(
                        2,
                        done: added,
                        title: "Click the \(plusIcon) button at the bottom of the list and choose \(name) in the file browser"
                    )
                    if control == .limited {
                        step(
                            3,
                            done: false,
                            warning: true,
                            title: "\(name) was added with Choose Apps, so it can't see your keyboard",
                            detail: "Remove \(name) from the list, add it again, and click Override System Protections."
                        )
                    } else {
                        step(
                            3,
                            done: overridden,
                            title: "Click the Override System Protections button",
                            detail: "Don't click Choose Apps — \(name) will not work with app-level permissions."
                        )
                    }
                    step(
                        4,
                        done: overridden,
                        title: "Click all of the red OK buttons to enable the red Allow System & App Protection Override button, and click it",
                        detail: "Your Mac will ask for your password or Touch ID to confirm."
                    )
                }
                box(done: inputMonitoringGranted) {
                    step(
                        5,
                        done: inputMonitoringGranted,
                        title: "Open \(privacyIcon) Privacy & Security → \(inputIcon) Input Monitoring, click the \(plusIcon) button and choose \(name)",
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

    private func box<Content: View>(done: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if done {
                    Color.green.opacity(0.14)
                } else {
                    Rectangle().fill(.background.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeInOut(duration: 0.25), value: done)
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
/// text runs so they can sit inline in a sentence.
enum SettingsGlyph {
    private static let side: CGFloat = 15

    /// Sized and lowered to centre on the cap height of 13 pt system text.
    static func inline(_ symbol: String, fill: NSColor, glyph: NSColor = .white) -> Text {
        Text(Image(nsImage: image(symbol, fill: fill, glyph: glyph))).baselineOffset(-3)
    }

    /// Drawn into a 3x bitmap: an image inside a line of text isn't
    /// re-rasterised for the display, so a 1x drawing comes out soft.
    private static func image(_ symbol: String, fill: NSColor, glyph: NSColor) -> NSImage {
        let scale: CGFloat = 3
        let pixels = Int(side * scale)
        let image = NSImage(size: NSSize(width: side, height: side))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return image }
        // Set before making the context so it draws in points, not pixels.
        rep.size = image.size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return image }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let box = NSRect(x: 0, y: 0, width: side, height: side)
            fill.setFill()
            NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5).fill()

            let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
                .applying(.init(paletteColors: [glyph]))
            if let mark = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                // Centre the visible glyph, not the image frame: symbol
                // images carry uneven margins around the drawing.
                let visible = mark.alignmentRect
                mark.draw(in: NSRect(
                    x: box.midX - visible.midX,
                    y: box.midY - visible.midY,
                    width: mark.size.width,
                    height: mark.size.height
                ))
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        image.addRepresentation(rep)
        return image
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
