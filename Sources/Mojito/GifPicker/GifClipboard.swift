import AppKit
import Foundation

/// Writes the bytes of an animated GIF to the system pasteboard.
///
/// `com.compuserve.gif` is the UTI receivers sniff for animated paste —
/// Slack, Discord, iMessage, Mail all animate from it. We also include a
/// `public.tiff` still as a fallback for receivers that pick image types
/// without GIF awareness.
@MainActor
enum GifClipboard {
    /// Fetches the GIF bytes from `url` and writes them to the pasteboard.
    /// Returns true on success.
    static func copy(from url: URL) async -> Bool {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return write(data: data)
        } catch {
            return false
        }
    }

    static func write(data: Data) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        var ok = pb.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
        // Still fallback for receivers that don't sniff the GIF UTI.
        if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
            _ = pb.setData(tiff, forType: .tiff)
            ok = ok || true
        }
        return ok
    }
}
