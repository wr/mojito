import SwiftUI
import AppKit

struct AboutSettingsView: View {
    @AppStorage(PrefsKey.donated) private var donated: Bool = false

    private let rowPadding: CGFloat = 2

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
    }

    private static let appIcon: NSImage =
        AppInfo.appIcon ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                Form {
                    donationSection

                    Section("Acknowledgements") {
                        acknowledgement("Emojibase", url: URL(string: "https://emojibase.dev")!)
                            .padding(.vertical, rowPadding)
                        acknowledgement("Sparkle", url: URL(string: "https://sparkle-project.org")!)
                            .padding(.vertical, rowPadding)
                        acknowledgement("KeyboardShortcuts", url: URL(string: "https://github.com/sindresorhus/KeyboardShortcuts")!)
                            .padding(.vertical, rowPadding)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)

                byline
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 6) {
            Image(nsImage: Self.appIcon)
                .resizable()
                .frame(width: 72, height: 72)
            Text(AppInfo.displayName)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("Version \(version) (\(build))")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Donation

    private var donationSection: some View {
        Section {
            HStack(alignment: .center, spacing: 14) {
                Image("Wells")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                    .overlay(alignment: .bottom) {
                    if donated {
                        HeartConfetti()
                            .frame(width: 96, height: 110)
                            .allowsHitTesting(false)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Support Wells")
                        .font(.headline)
                    Text("\(AppInfo.displayName) is forever free, but your support helps fund future projects. Thank you!")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button("Donate") {
                    NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/wellsriley")!)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, rowPadding)

            Toggle("I donated", isOn: $donated)
                .onChange(of: donated) { oldValue, newValue in
                    if !oldValue && newValue { sayThankYou() }
                }
                .padding(.vertical, rowPadding)
        }
    }

    // MARK: - Byline

    private var byline: some View {
        VStack(spacing: 8) {
            Button("Report an issue") {
                NSWorkspace.shared.open(URL(string: "https://github.com/wr/mojito/issues/new")!)
            }

            Link("Website", destination: URL(string: "https://github.com/wr/mojito")!)
                .font(.callout)

            if !copyright.isEmpty {
                Text(copyright)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Acknowledgement row

    private func acknowledgement(_ name: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack {
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sayThankYou() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        task.arguments = ["-v", "Fred", "-r", "300", "Thank you"]
        try? task.run()
    }
}

// MARK: - Clear stats button

/// Destructive button + confirmation dialog used by the Easter Eggs and
/// Privacy & Permissions panes. Owns its own confirmation state so the two
/// callers don't have to duplicate it.
struct ClearStatsButton: View {
    @EnvironmentObject private var engine: Engine
    @State private var confirm = false
    var isDisabled: Bool = false

    var body: some View {
        Button("Clear stats...") { confirm = true }
            .disabled(isDisabled)
            .confirmationDialog(
                "Clear all emoji usage stats?",
                isPresented: $confirm,
                titleVisibility: .visible
            ) {
                Button("Clear stats", role: .destructive) {
                    engine.clearUsageStats()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will erase your autocomplete stats and Top 8. Settings and exclusions won't be changed.")
            }
    }
}

// MARK: - Heart confetti

private struct HeartConfetti: View {
    @State private var configs: [HeartConfig] = (0..<4).map { _ in HeartConfig() }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let base = ctx.resolve(Text("❤️").font(.system(size: 10)))
                for config in configs {
                    let t = (elapsed + config.phaseOffset).truncatingRemainder(dividingBy: config.cycle)
                    guard t > 0, t < config.visibleDuration else { continue }

                    let progress = t / config.visibleDuration
                    let y = size.height * (1.0 - progress) - 6
                    let wiggle = sin(t * config.wiggleFreq + config.wigglePhase) * 8
                    let x = size.width / 2 + wiggle + config.xBias
                    let opacity: Double
                    if progress < 0.4 {
                        opacity = progress / 0.4
                    } else {
                        opacity = max(0, 1.0 - (progress - 0.4) / 0.6)
                    }

                    var c = ctx
                    c.opacity = opacity
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .degrees(config.rotation))
                    c.scaleBy(x: config.scale, y: config.scale)
                    c.draw(base, at: .zero, anchor: .center)
                }
            }
        }
    }
}

private struct HeartConfig {
    let phaseOffset: Double
    let cycle: Double
    let visibleDuration: Double
    let wiggleFreq: Double
    let wigglePhase: Double
    let xBias: Double
    let scale: CGFloat
    let rotation: Double

    init() {
        self.phaseOffset = .random(in: 0...5)
        self.cycle = .random(in: 5.0...8.0)
        self.visibleDuration = .random(in: 1.0...1.8)
        self.wiggleFreq = .random(in: 2.5...4.5)
        self.wigglePhase = .random(in: 0...(.pi * 2))
        self.xBias = .random(in: -6...6)
        self.scale = .random(in: 0.7...1.2)
        self.rotation = .random(in: -25...25)
    }
}
