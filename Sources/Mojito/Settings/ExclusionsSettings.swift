import SwiftUI
import AppKit

/// Hand-rolled instead of `List(.bordered)` because the native list
/// expands to fill height — we want each card sized to its content so
/// two short lists can stack without clipping.
struct ExclusionsSettingsView: View {
    @EnvironmentObject private var store: ExclusionStore
    @State private var selectedApp: String?
    @State private var selectedPattern: String?
    @State private var showAddSheet = false
    @State private var newPattern: String = ""

    private var visibleBundleIDs: [String] {
        store.bundleIDs.sorted().filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
    }

    private var sortedPatterns: [String] {
        store.urlPatterns.sorted()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                BoxedList(
                    header: "Prevent \(AppInfo.displayName) from triggering inside these apps.",
                    items: visibleBundleIDs,
                    selected: $selectedApp,
                    onAdd: addApp,
                    onRemove: {
                        if let s = selectedApp {
                            store.bundleIDs.remove(s)
                            selectedApp = nil
                        }
                    },
                    row: appRow
                )

                BoxedList(
                    header: "Prevent \(AppInfo.displayName) from triggering on these sites. `*` matches a subdomain.",
                    items: sortedPatterns,
                    selected: $selectedPattern,
                    onAdd: { newPattern = ""; showAddSheet = true },
                    onRemove: {
                        if let s = selectedPattern {
                            store.urlPatterns.remove(s)
                            selectedPattern = nil
                        }
                    },
                    row: siteRow
                )
            }
            .padding(20)
        }
        .sheet(isPresented: $showAddSheet) {
            AddWebsiteSheet(pattern: $newPattern) { trimmed in
                store.urlPatterns.insert(trimmed)
                showAddSheet = false
            } onCancel: {
                showAddSheet = false
            }
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
            store.bundleIDs.insert(id)
        }
    }
}

// MARK: - Boxed list

/// Sizes to content vertically. Matches System Settings → Privacy.
private struct BoxedList<ID: Hashable, RowContent: View>: View {
    let header: String
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
        Text(.init(header))
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
