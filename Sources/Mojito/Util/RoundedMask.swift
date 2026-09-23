import AppKit

extension NSVisualEffectView {
    /// Rounds the material itself, not just the view's drawing. With
    /// `.behindWindow` blending the window server composites the blur
    /// outside the view's layer, so `layer.cornerRadius` leaves a
    /// rectangular backdrop (and a rectangular window shadow) behind the
    /// rounded content. `maskImage` is the shape the server honours.
    func applyRoundedMask(radius: CGFloat) {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        maskImage = image
    }
}
