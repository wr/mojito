import AppKit

/// Shared frame math for the caret-anchored floating panels (emoji picker,
/// GIF picker): pick the screen hosting the anchor, prefer dropping the panel
/// below the anchor, flip above when there's no room downward, then clamp
/// into the screen's visible frame.
@MainActor
enum PanelPositioner {
    /// How to find the screen hosting the anchor. The two pickers probe
    /// differently; both strategies are kept so placement stays unchanged.
    enum ScreenProbe {
        /// Anchor center first, then any intersecting screen, before falling
        /// back to `NSScreen.main`. The center probe survives caret rects that
        /// sit exactly on a screen edge.
        case anchorCenter
        /// Anchor origin only, then `NSScreen.main`.
        case anchorOrigin
    }

    static func screen(for anchor: CGRect, probe: ScreenProbe) -> NSScreen {
        switch probe {
        case .anchorCenter:
            let center = CGPoint(x: anchor.midX, y: anchor.midY)
            if let hit = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
                return hit
            }
            if let hit = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
                return hit
            }
        case .anchorOrigin:
            if let hit = NSScreen.screens.first(where: { $0.frame.contains(anchor.origin) }) {
                return hit
            }
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    /// Frame for a `size` panel anchored to `anchor`. `clampMinY` additionally
    /// keeps the frame above the visible frame's bottom edge even when the
    /// panel is taller than the screen.
    static func frame(
        anchor: CGRect,
        size: CGSize,
        probe: ScreenProbe,
        clampMinY: Bool
    ) -> CGRect {
        let visible = screen(for: anchor, probe: probe).visibleFrame
        let gap: CGFloat = 6

        let belowOriginY = anchor.minY - size.height - gap
        let aboveOriginY = anchor.maxY + gap

        // Prefer below; flip above if no room downward.
        var origin = CGPoint(
            x: anchor.minX,
            y: belowOriginY >= visible.minY ? belowOriginY : aboveOriginY
        )

        if origin.y + size.height > visible.maxY {
            origin.y = visible.maxY - size.height - gap
        }
        if clampMinY, origin.y < visible.minY {
            origin.y = visible.minY + gap
        }

        if origin.x + size.width > visible.maxX {
            origin.x = visible.maxX - size.width - 8
        }
        if origin.x < visible.minX {
            origin.x = visible.minX + 8
        }

        return CGRect(origin: origin, size: size)
    }

    /// Fallback anchor when there's no caret rect: a thin caret-sized rect at
    /// the current mouse location.
    static func mouseAnchor() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x, y: mouse.y, width: 1, height: 16)
    }
}
