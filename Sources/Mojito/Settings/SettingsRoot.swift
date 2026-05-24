import AppKit
import SwiftUI

struct SettingsRoot: View {
    enum Tab: Hashable, CaseIterable, Identifiable {
        case general, exclusions, easterEggs, privacy, about
        var id: Self { self }

        var title: String {
            switch self {
            case .general:    return "General"
            case .exclusions: return "Exclusions"
            case .easterEggs: return "Easter eggs"
            case .privacy:    return "Privacy"
            case .about:      return "About"
            }
        }

        var symbol: String {
            switch self {
            case .general:    return "gearshape"
            case .exclusions: return "xmark.octagon"
            case .easterEggs: return "sparkles"
            case .privacy:    return "lock.shield"
            case .about:      return "info.circle"
            }
        }
    }

    @State private var selection: Tab = .general
    @State private var hostWindow: NSWindow?

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
                case .exclusions: ExclusionsSettingsView()
                case .easterEggs: EasterEggsSettingsView()
                case .privacy:    PrivacyPermissionsSettingsView()
                case .about:      AboutSettingsView()
                }
            }
            .frame(minWidth: 460, minHeight: 360)
            // Hide the Form's opaque grouped background so the title bar's
            // translucent material can blur the scrolling content beneath it
            // (the "glass fade" macOS Settings has).
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
    }
}

/// Bridges SwiftUI → the hosting NSWindow so we can reach AppKit-only
/// properties (window title, in our case). The wrapped view is invisible
/// and zero-sized; its only job is to expose `view.window`.
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
