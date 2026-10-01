import AppKit

/// NSPopover's Liquid Glass, for our borderless panels. A bare
/// `NSGlassEffectView` renders the clearer regular glass, which reads as a
/// flat grey slab over light content. NSPopover hosts the same view with the
/// private `_variant` 20: frostier, lighter, and the look of the system
/// emoji picker.
///
/// Dark mode keeps the regular glass. Over a bright backdrop variant 20
/// turns light grey while the content stays dark-scheme, leaving white text
/// on light grey (NSPopover has the same problem; our rows are text, so it
/// matters more here).
@available(macOS 26.0, *)
enum PopoverGlass {
    /// NSPopover's own glass radius.
    static let cornerRadius: CGFloat = 20

    static func make(contentView: NSView) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.contentView = contentView
        glass.translatesAutoresizingMaskIntoConstraints = false
        return glass
    }

    /// Call whenever the panel's appearance is (re)set.
    static func match(_ glass: NSGlassEffectView, to appearance: NSAppearance) {
        // Assigning `style` rewrites the private variant, even when the
        // style is unchanged — that's what undoes a previous light-mode pass.
        glass.style = .regular
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        // KVC on a missing key raises, so if a future macOS drops the key
        // this degrades to the regular glass.
        guard !isDark, glass.responds(to: NSSelectorFromString("set_variant:")) else { return }
        glass.setValue(20, forKey: "_variant")
    }
}
