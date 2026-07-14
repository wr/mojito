import AppKit
import SwiftUI

struct SettingsRoot: View {
    enum Tab: Hashable, CaseIterable, Identifiable {
        case general, shortcuts, exclusions, easterEggs, privacy, about
        var id: Self { self }

        var title: String {
            switch self {
            case .general:    return String(localized: "General")
            case .shortcuts:  return String(localized: "Shortcuts")
            case .exclusions: return String(localized: "Exclusions")
            case .easterEggs: return String(localized: "Easter eggs")
            case .privacy:    return String(localized: "Privacy")
            case .about:      return String(localized: "About")
            }
        }

        var symbol: String {
            switch self {
            case .general:    return "gearshape"
            case .shortcuts:  return "text.badge.plus"
            case .exclusions: return "xmark.octagon"
            case .easterEggs: return "sparkles"
            case .privacy:    return "lock.shield"
            case .about:      return "info.circle"
            }
        }
    }

    @State private var selection: Tab = .general
    @State private var hostWindow: NSWindow?
    @ObservedObject private var nav = SettingsNavigator.shared

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $selection) { tab in
                Label(tab.title, systemImage: tab.symbol)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Group {
                switch selection {
                case .general:    GeneralSettingsView()
                case .shortcuts:  CustomShortcutsSettingsView()
                case .exclusions: ExclusionsSettingsView()
                case .easterEggs: EasterEggsSettingsView()
                case .privacy:    PrivacyPermissionsSettingsView()
                case .about:      AboutSettingsView()
                }
            }
            .frame(minWidth: 460, minHeight: 360)
            // Hide the Form bg so the title bar can blur scrolling
            // content underneath (macOS Settings' glass fade).
            .scrollContentBackground(.hidden)
        }
        .frame(width: 700, height: 500)
        .background(WindowAccessor { window in
            hostWindow = window
            window?.title = selection.title
        })
        .onChange(of: selection) { _, new in
            hostWindow?.title = new.title
        }
        .onAppear { applyRequestedTab() }
        .onChange(of: nav.requestedTab) { _, _ in applyRequestedTab() }
    }

    /// Honors a pending tab request from `SettingsNavigator`, then clears it so
    /// a plain Settings open still defaults to General.
    private func applyRequestedTab() {
        guard let tab = nav.requestedTab else { return }
        selection = tab
        nav.requestedTab = nil
    }
}

/// Zero-sized bridge to the hosting NSWindow for AppKit-only props
/// (window title here).
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { [weak v] in
            onResolve(v?.window)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
