import AppKit
import SwiftUI

/// The system emoji picker's Liquid Glass, for our borderless panels, from
/// public API only. NSPopover gets its look from a private glass variant,
/// but those are numbered, and macOS 27.2 renumbered them: the number we
/// once borrowed now renders a clear lens that hides the panel's edges.
///
/// Light mode is clear glass under a 0.25 white veil, which reads like the
/// system picker (~247 over white, ~117 over black). Regular glass reads
/// greyer over white and lifts dark backdrops into a light slab.
///
/// Dark mode keeps the regular glass, unveiled. Over a bright backdrop
/// clear glass turns light grey while the content stays dark-scheme,
/// leaving white text on light grey.
@available(macOS 26.0, *)
enum PopoverGlass {
    private static let lightVeil = NSColor.white.withAlphaComponent(0.25).cgColor

    static func make(contentView: NSView, cornerRadius: CGFloat) -> NSGlassEffectView {
        let veil = NSView()
        veil.wantsLayer = true
        veil.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        veil.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: veil.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: veil.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: veil.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: veil.bottomAnchor),
        ])

        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.contentView = veil
        glass.translatesAutoresizingMaskIntoConstraints = false
        return glass
    }

    /// Call whenever the panel's appearance is (re)set.
    static func match(_ glass: NSGlassEffectView, to appearance: NSAppearance) {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        glass.style = isDark ? .regular : .clear
        glass.contentView?.layer?.backgroundColor = isDark ? nil : lightVeil
    }
}

extension Color {
    /// Selected / hovered cell fill in the pickers: a translucent darken, as
    /// in the system picker, so it still reads over a dark backdrop. The
    /// opaque unemphasized-selection grey turns into a bright bar there.
    static let pickerSelection = Color.primary.opacity(0.16)
}
