import SwiftUI
import KeyboardShortcuts

struct GeneralSettingsView: View {
    @AppStorage(PrefsKey.launchAtLogin) private var launchAtLogin: Bool = false
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

                Toggle("Rank frequently used emoji higher", isOn: $useFrequencyBoost)
                    .toggleStyle(.switch)

                LabeledContent {
                    HStack(spacing: 8) {
                        Button("Check now") {
                            UpdaterCoordinator.shared.checkForUpdates()
                        }
                        Toggle("", isOn: $autoUpdates)
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

/// A horizontal row of skin-tone swatches (👋 in each tone). Selected swatch
/// is outlined; tapping a swatch persists the choice to `PrefsKey.skinTone`.
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
