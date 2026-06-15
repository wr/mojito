import SwiftUI
import KeyboardShortcuts

struct GeneralSettingsView: View {
    @AppStorage(PrefsKey.launchAtLogin) private var launchAtLogin: Bool = false
    @AppStorage(PrefsKey.showMenuBarIcon) private var showMenuBarIcon: Bool = true
    @AppStorage(PrefsKey.useFrequencyBoost) private var useFrequencyBoost: Bool = true
    @AppStorage(PrefsKey.skinTone) private var skinToneRaw: String = SkinTone.default.rawValue
    @AppStorage(PrefsKey.emoticonsEnabled) private var emoticonsEnabled: Bool = true
    @AppStorage(PrefsKey.arrowConversionEnabled) private var arrowConversionEnabled: Bool = true
    @AppStorage(PrefsKey.symbolsEnabled) private var symbolsEnabled: Bool = false
    @AppStorage(PrefsKey.symbolsRequireDoubleColon) private var symbolsRequireDoubleColon: Bool = false
    @AppStorage(PrefsKey.gifSearchEnabled) private var gifSearchEnabled: Bool = true
    @AppStorage(PrefsKey.telemetryEnabled) private var telemetryEnabled: Bool = true
    @AppStorage(PrefsKey.eggsEnabled) private var eggsEnabled: Bool = true
    @AppStorage(PrefsKey.eggDiscoverySoundEnabled) private var eggDiscoverySound: Bool = true
    @AppStorage(PrefsKey.eggEffectSoundsEnabled) private var eggEffectSounds: Bool = true
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

                Toggle(isOn: $telemetryEnabled) {
                    HStack(spacing: 4) {
                        Text("Share anonymous usage stats")
                        StatsHelpButton()
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: telemetryEnabled) { _, _ in
                    // Interacting with the toggle is itself the consent decision.
                    UserDefaults.standard.set(true, forKey: PrefsKey.telemetryConsentSeen)
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
                Toggle("Convert text arrows (`->` to →)", isOn: $arrowConversionEnabled)
                    .toggleStyle(.switch)
            }

            QuickAccessSection()

            Section("GIFs and Symbols") {
                Toggle(isOn: $gifSearchEnabled) {
                    TitleAndCaption(
                        title: "GIF search",
                        caption: "Type `:::` then a search term to insert a GIF from Giphy."
                    )
                }
                .toggleStyle(.switch)
                Toggle(isOn: $symbolsEnabled) {
                    TitleAndCaption(
                        title: "Symbols",
                        caption: "Include ★ ⌘ ⌥ and similar characters in results (experimental)."
                    )
                }
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
                Text("Pausing")
            } footer: {
                Text("Press the same shortcut again while paused to resume.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable easter eggs", isOn: $eggsEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: eggsEnabled) { _, isOn in
                        // Records .k53 once; it's persistent, so flipping
                        // eggs back on keeps it.
                        if !isOn { EasterEggTracker.record(.k53) }
                    }
                if eggsEnabled {
                    Toggle("Play “Easter egg found” sound effect", isOn: $eggDiscoverySound)
                        .toggleStyle(.switch)
                    Toggle("Play sounds within easter eggs", isOn: $eggEffectSounds)
                        .toggleStyle(.switch)
                }
            } header: {
                Text("Easter eggs")
            } footer: {
                if eggsEnabled {
                    Text("Easter eggs still play on screen — these control sound only.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct TitleAndCaption: View {
    let title: LocalizedStringKey
    let caption: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct StatsHelpButton: View {
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
            Text("Anonymous, aggregate counts only — no identifiers. The full dataset is public at [mojito.wells.ee/stats](https://mojito.wells.ee/stats).")
                .padding(12)
                .frame(width: 260)
        }
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
