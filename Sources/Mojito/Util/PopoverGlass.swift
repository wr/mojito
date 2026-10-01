import AppKit
import SwiftUI

/// The system emoji picker's Liquid Glass, for our borderless panels. A bare
/// `NSGlassEffectView` renders the clearer regular glass, which reads as a
/// flat grey slab over light content. NSPopover hosts the same view with the
/// private `_variant` 20, which is frostier.
///
/// Even variant 20 sits darker than the system picker, which reads ~239
/// over light content and ~115 over black, where bare glass gives ~232 and
/// 71. A 0.25 white veil lands on both; a heavier one turns the panel into
/// a light slab over dark backdrops and hides what's behind it.
///
/// Dark mode keeps the regular glass, unveiled. Over a bright backdrop
/// variant 20 turns light grey while the content stays dark-scheme, leaving
/// white text on light grey (NSPopover has the same problem; our rows are
/// text, so it matters more here).
@available(macOS 26.0, *)
enum PopoverGlass {
    /// NSPopover's own glass radius.
    static let cornerRadius: CGFloat = 20

    private static let lightVeil = NSColor.white.withAlphaComponent(0.25).cgColor

    static func make(contentView: NSView) -> NSGlassEffectView {
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
        // Assigning `style` rewrites the private variant, even when the
        // style is unchanged — that's what undoes a previous light-mode pass.
        glass.style = .regular
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        glass.contentView?.layer?.backgroundColor = isDark ? nil : lightVeil
        // KVC on a missing key raises, so if a future macOS drops the key
        // this degrades to the regular glass.
        guard !isDark, glass.responds(to: NSSelectorFromString("set_variant:")) else { return }
        glass.setValue(20, forKey: "_variant")
    }
}

extension Color {
    /// Selected / hovered cell fill in the pickers. On Liquid Glass it's a
    /// translucent darken, as in the system picker, so it still reads over a
    /// dark backdrop; the opaque unemphasized-selection grey turns into a
    /// bright bar there.
    static var pickerSelection: Color {
        if #available(macOS 26.0, *) { return Color.primary.opacity(0.16) }
        return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }
}
