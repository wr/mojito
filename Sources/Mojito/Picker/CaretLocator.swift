import AppKit
import ApplicationServices
import os.log

@MainActor
enum CaretLocator {
    private static let log = OSLog(subsystem: "ee.wells.Mojito", category: "CaretLocator")

    /// Returns a screen-space (bottom-left origin) rect for the current text caret, or nil.
    ///
    /// The big risk in AX-driven caret tracking is apps that return junk bounds. We defend
    /// by requiring the caret rect to sit inside the focused element's own frame — if it
    /// doesn't, we treat the result as untrusted and return nil so the caller can fall back.
    static func caretRect() -> CGRect? {
        // Prefer the cached focused element — it's kept fresh by AX observer
        // notifications and avoids a synchronous cross-process IPC per call.
        // Fall back to a fresh system-wide lookup if the cache is empty
        // (transitions, AX unusable).
        let focused: AXUIElement
        if let cached = FocusedElementCache.shared.element {
            focused = cached
        } else {
            let system = AXUIElementCreateSystemWide()
            guard let focusedRef = copyAttribute(system, key: kAXFocusedUIElementAttribute) else { return nil }
            focused = focusedRef as! AXUIElement
        }
        let elementFrame = elementFrame(of: focused)

        if let rect = caretBounds(of: focused), isPlausibleCaret(rect, withinElementFrame: elementFrame) {
            os_log("caret via AX bounds: %{public}@", log: log, type: .info, "\(rect)")
            return rect
        }

        // Fallback: anchor at the top-left of the focused element (where the caret usually
        // is in an empty / start-of-document text view). In AppKit screen coordinates
        // (bottom-left origin) the TOP of the element is `frame.maxY`, NOT `frame.minY` —
        // using minY here previously dropped the picker at the *bottom* of the text view.
        if let frame = elementFrame, isOnScreen(frame), frame.width < 4000, frame.height < 4000 {
            let caretHeight: CGFloat = max(16, min(frame.height, 22))
            let rect = CGRect(
                x: frame.minX + 4,
                y: frame.maxY - caretHeight - 2,
                width: 1,
                height: caretHeight
            )
            os_log("caret via element fallback: %{public}@ (frame %{public}@)", log: log, type: .info, "\(rect)", "\(frame)")
            return rect
        }

        os_log("caret unavailable — no AX bounds and no usable element frame", log: log, type: .info)
        return nil
    }

    // MARK: - AX strategies

    private static func caretBounds(of element: AXUIElement) -> CGRect? {
        guard let rangeRef = copyAttribute(element, key: kAXSelectedTextRangeAttribute) else { return nil }
        var range = CFRange()
        AXValueGetValue((rangeRef as! AXValue), .cfRange, &range)

        for length in [max(range.length, 1), 0] {
            var queryRange = CFRange(location: range.location, length: length)
            guard let queryValue = AXValueCreate(.cfRange, &queryRange) else { continue }

            var boundsRef: AnyObject?
            let status = AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                queryValue,
                &boundsRef
            )
            guard status == .success, let boundsRef else { continue }

            var rect = CGRect.zero
            AXValueGetValue((boundsRef as! AXValue), .cgRect, &rect)
            guard rect.width >= 0, rect.height > 0 else { continue }

            return convertFromAXScreen(rect)
        }
        return nil
    }

    private static func elementFrame(of element: AXUIElement) -> CGRect? {
        guard let posRef = copyAttribute(element, key: kAXPositionAttribute as String) else { return nil }
        guard let sizeRef = copyAttribute(element, key: kAXSizeAttribute as String) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue((posRef as! AXValue), .cgPoint, &origin)
        AXValueGetValue((sizeRef as! AXValue), .cgSize, &size)
        guard size.width > 0, size.height > 0 else { return nil }
        return convertFromAXScreen(CGRect(origin: origin, size: size))
    }

    // MARK: - Validation

    private static func isPlausibleCaret(_ rect: CGRect, withinElementFrame elementFrame: CGRect?) -> Bool {
        guard isOnScreen(rect) else {
            os_log("rejecting caret rect %{public}@ — not on any screen", log: log, type: .info, "\(rect)")
            return false
        }
        if let elementFrame {
            // Caret should be inside the focused element (allowing some slack for text overflow).
            let slack: CGFloat = 8
            let expanded = elementFrame.insetBy(dx: -slack, dy: -slack)
            if !expanded.contains(CGPoint(x: rect.midX, y: rect.midY)) {
                os_log(
                    "rejecting caret rect %{public}@ — outside focused element %{public}@",
                    log: log, type: .info, "\(rect)", "\(elementFrame)"
                )
                return false
            }
        }
        return true
    }

    private static func isOnScreen(_ rect: CGRect) -> Bool {
        for screen in NSScreen.screens where screen.frame.intersects(rect) {
            return true
        }
        return false
    }

    // MARK: - Coordinate conversion

    /// AX uses top-left origin rooted at the menu-bar screen. AppKit uses bottom-left origin
    /// rooted at the same screen. Flip Y.
    private static func convertFromAXScreen(_ rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        let primaryHeight = primary.frame.height
        let flippedY = primaryHeight - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)
    }

    private static func copyAttribute(_ element: AXUIElement, key: String) -> AnyObject? {
        var ref: AnyObject?
        return AXUIElementCopyAttributeValue(element, key as CFString, &ref) == .success ? ref : nil
    }
}
