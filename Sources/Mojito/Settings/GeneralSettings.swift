import SwiftUI
import KeyboardShortcuts

struct GeneralSettingsView: View {
    @AppStorage(PrefsKey.launchAtLogin) private var launchAtLogin: Bool = false
    @AppStorage(PrefsKey.showMenuBarIcon) private var showMenuBarIcon: Bool = true
    @AppStorage(PrefsKey.useFrequencyBoost) private var useFrequencyBoost: Bool = true
    @AppStorage(PrefsKey.skinTone) private var skinToneRaw: String = SkinTone.default.rawValue
    @AppStorage(PrefsKey.emoticonsEnabled) private var emoticonsEnabled: Bool = true
    @AppStorage(PrefsKey.symbolsEnabled) private var symbolsEnabled: Bool = false
    @AppStorage(PrefsKey.symbolsRequireDoubleColon) private var symbolsRequireDoubleColon: Bool = false
    @State private var autoUpdates: Bool = UpdaterCoordinator.shared.automaticUpdates

    var body: some View {
        Form {
            Section {
                Toggle("Start at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.apply(newValue)
                    }
                    .toggleStyle(.switch)
                    .onAppear { LaunchAtLogin.syncFromSystem() }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                        LaunchAtLogin.syncFromSystem()
                    }

                Toggle(isOn: $showMenuBarIcon) {
                    HStack(spacing: 4) {
                        Text("Show icon in menu bar")
                        if #available(macOS 26.0, *) {
                            MenuBarHelpButton()
                        }
                    }
                }
                .toggleStyle(.switch)

                LabeledContent {
                    HStack(spacing: 8) {
                        Button("Check now") {
                            UpdaterCoordinator.shared.checkForUpdates()
                        }
                        Toggle("Automatic updates", isOn: $autoUpdates)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: autoUpdates) { _, newValue in
                                UpdaterCoordinator.shared.automaticUpdates = newValue
                            }
                    }
                } label: {
                    Text("Automatic updates")
                }
            }

            Section("Emoji") {
                HStack(alignment: .center) {
                    Text("Skin tone")
                    Spacer()
                    SkinToneSwatches(selection: $skinToneRaw)
                }
                Toggle("Rank frequently used emoji higher", isOn: $useFrequencyBoost)
                    .toggleStyle(.switch)
                Toggle("Convert emoticons (`:D` → 😃)", isOn: $emoticonsEnabled)
                    .toggleStyle(.switch)
                Toggle("Include symbols (experimental)", isOn: $symbolsEnabled)
                    .toggleStyle(.switch)
                if symbolsEnabled {
                    Toggle("Require `::` to search symbols", isOn: $symbolsRequireDoubleColon)
                        .toggleStyle(.switch)
                        .padding(.leading, 20)
                }
            }

            Section {
                KeyboardShortcuts.Recorder("Pause for 1 hour", name: .pauseHour)
                KeyboardShortcuts.Recorder("Pause until tomorrow", name: .pauseUntilTomorrow)
            } header: {
                Text("Keyboard shortcuts")
            } footer: {
                Text("Press the same shortcut again while paused to resume.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

@available(macOS 26.0, *)
private struct MenuBarHelpButton: View {
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShown, arrowEdge: .top) {
            Text("If the icon doesn't appear in the menu bar, check **System Settings → Menu Bar → \"Allow in the Menu Bar\"**.")
                .padding(12)
                .frame(width: 280)
        }
    }
}

private struct SkinToneSwatches: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SkinTone.allCases) { tone in
                Button {
                    selection = tone.rawValue
                } label: {
                    Text(tone.swatchEmoji)
                        .font(.system(size: 20))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selection == tone.rawValue
                                      ? Color.accentColor.opacity(0.20)
                                      : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    selection == tone.rawValue ? Color.accentColor : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(tone.displayName)
            }
        }
    }
}
