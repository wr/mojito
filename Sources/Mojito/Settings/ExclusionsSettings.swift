import SwiftUI
import AppKit

/// Hand-rolled instead of `List(.bordered)` because the native list
/// expands to fill height — we want each card sized to its content so
/// two short lists can stack without clipping.
struct ExclusionsSettingsView: View {
    @EnvironmentObject private var store: ExclusionStore
    @AppStorage(PrefsKey.gifBypassExclusions) private var gifBypassExclusions: Bool = true
    @State private var selectedApp: String?
    @State private var selectedPattern: String?
    @State private var showAddSheet = false
    @State private var newPattern: String = ""

    private var activeBundleIDs: Set<String> {
        store.mode == .allowlist ? store.allowedBundleIDs : store.bundleIDs
    }

    private var visibleBundleIDs: [String] {
        activeBundleIDs.sorted().filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
    }

    private var sortedPatterns: [String] {
        (store.mode == .allowlist ? store.allowedURLPatterns : store.urlPatterns).sorted()
    }

    private var appsHeader: LocalizedStringKey {
        store.mode == .allowlist
            ? "These apps will trigger \(AppInfo.displayName)."
            : "These apps won't trigger \(AppInfo.displayName)."
    }

    private var sitesHeader: LocalizedStringKey {
        store.mode == .allowlist
            ? "These sites will trigger \(AppInfo.displayName).\n`*` matches a subdomain."
            : "These sites won't trigger \(AppInfo.displayName).\n`*` matches a subdomain."
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                modePicker

                BoxedList(
                    header: appsHeader,
                    items: visibleBundleIDs,
                    selected: $selectedApp,
                    onAdd: addApp,
                    onRemove: removeSelectedApp,
                    row: appRow
                )

                BoxedList(
                    header: sitesHeader,
                    items: sortedPatterns,
                    selected: $selectedPattern,
                    onAdd: { newPattern = ""; showAddSheet = true },
                    onRemove: removeSelectedPattern,
                    row: siteRow
                )

                BoxedToggle(
                    header: "GIF search override",
                    title: "Always let GIF search work",
                    caption: "`:::` opens the GIF picker regardless of the lists above.",
                    isOn: $gifBypassExclusions
                )
            }
            .padding(20)
        }
        .sheet(isPresented: $showAddSheet) {
            AddWebsiteSheet(pattern: $newPattern) { trimmed in
                insertPattern(trimmed)
                showAddSheet = false
            } onCancel: {
                showAddSheet = false
            }
        }
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        // Local binding keeps the selection drawn from `store.mode` so it
        // updates whenever any other surface flips the mode.
        let binding = Binding<ExclusionMode>(
            get: { store.mode },
            set: { newValue in
                guard newValue != store.mode else { return }
                store.mode = newValue
                selectedApp = nil
                selectedPattern = nil
            }
        )
        return HStack(spacing: 6) {
            Text("\(AppInfo.displayName) runs")
            Picker("", selection: binding) {
                Text("everywhere except the apps & sites below").tag(ExclusionMode.denylist)
                Text("only in the apps & sites below").tag(ExclusionMode.allowlist)
            }
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 0)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func appRow(_ bundleID: String) -> some View {
        HStack(spacing: 10) {
            appIcon(for: bundleID)
                .frame(width: 28, height: 28)
            Text(displayName(for: bundleID))
            Spacer()
        }
    }

    @ViewBuilder
    private func siteRow(_ pattern: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 20))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
            Text(pattern)
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
    }

    // MARK: - Helpers

    private func appIcon(for bundleID: String) -> some View {
        let icon: NSImage = {
            if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return NSWorkspace.shared.icon(forFile: path.path)
            }
            return NSImage(systemSymbolName: "questionmark.app.dashed", accessibilityDescription: nil) ?? NSImage()
        }()
        return Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
    }

    private func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                   ?? (bundle.infoDictionary?["CFBundleName"] as? String) {
            return name
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    // MARK: - Actions

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
            switch store.mode {
            case .denylist:  store.bundleIDs.insert(id)
            case .allowlist: store.allowedBundleIDs.insert(id)
            }
        }
    }

    private func removeSelectedApp() {
        guard let s = selectedApp else { return }
        switch store.mode {
        case .denylist:  store.bundleIDs.remove(s)
        case .allowlist: store.allowedBundleIDs.remove(s)
        }
        selectedApp = nil
    }

    private func insertPattern(_ pattern: String) {
        switch store.mode {
        case .denylist:  store.urlPatterns.insert(pattern)
        case .allowlist: store.allowedURLPatterns.insert(pattern)
        }
    }

    private func removeSelectedPattern() {
        guard let s = selectedPattern else { return }
        switch store.mode {
        case .denylist:  store.urlPatterns.remove(s)
        case .allowlist: store.allowedURLPatterns.remove(s)
        }
        selectedPattern = nil
    }
}

// MARK: - Boxed list

/// Sizes to content vertically. Matches System Settings → Privacy.
/// Single-row card that visually matches `BoxedList`'s chrome (rounded
/// secondary background + hairline border + same header/divider/body
/// layout), so feature toggles sit alongside the exclusion lists at the
/// same width without floating.
private struct BoxedToggle: View {
    let header: LocalizedStringKey
    let title: LocalizedStringKey
    let caption: LocalizedStringKey
    @Binding var isOn: Bool

    private let cornerRadius: CGFloat = 10
    private let innerSeparator = Color.primary.opacity(0.08)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            innerSeparator.frame(height: 0.5)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

private struct BoxedList<ID: Hashable, RowContent: View>: View {
    let header: LocalizedStringKey
    let items: [ID]
    @Binding var selected: ID?
    let onAdd: () -> Void
    let onRemove: () -> Void
    @ViewBuilder let row: (ID) -> RowContent

    private let cornerRadius: CGFloat = 10
    /// Past the icon column so the hairline aligns with row text.
    private let separatorInset: CGFloat = 50
    /// `separatorColor` is too dark for inside rows — the system uses
    /// a lighter inner hairline.
    private let innerSeparator = Color.primary.opacity(0.08)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            boundaryLine
            rowsView
            boundaryLine
            footerView
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private var headerView: some View {
        Text(header)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    /// `Divider()` renders too dark; reuse the inner-hairline color full-width.
    private var boundaryLine: some View {
        innerSeparator.frame(height: 0.5)
    }

    private var rowsView: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element) { idx, id in
                row(id)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(selected == id ? Color.accentColor : Color.clear)
                    .foregroundStyle(selected == id ? Color.white : Color.primary)
                    .onTapGesture { selected = id }

                if idx < items.count - 1 {
                    innerSeparator
                        .frame(height: 0.5)
                        .padding(.leading, separatorInset)
                }
            }
        }
    }

    private var footerView: some View {
        HStack(spacing: 0) {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            // Unconstrained so it fills the HStack — matches System Settings.
            Divider()

            Button(action: onRemove) {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(selected == nil)

            Spacer()
        }
        // Distinct strip at the card's bottom edge.
        .background(Color.primary.opacity(0.04))
    }
}

// MARK: - Add website sheet

private struct AddWebsiteSheet: View {
    @Binding var pattern: String
    let onAdd: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add website")
                .font(.headline)

            TextField("e.g. mail.google.com or *.notion.so", text: $pattern)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var trimmed: String {
        pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        let t = trimmed
        guard !t.isEmpty else { return }
        onAdd(t)
    }
}
