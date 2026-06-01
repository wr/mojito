import AppKit
import Foundation

/// Writes an animated GIF to the system pasteboard so a synthetic ⌘V lands it
/// in the focused app — animation intact.
///
/// The load-bearing representation is a **file URL** to a temp `.gif`, not raw
/// image bytes. Electron/Chromium apps (Slack, Discord) flatten any inline
/// pasteboard *image* to a single static frame when they read it; handed a
/// file instead, they run it through their normal upload path (same as
/// drag-drop) and it animates. `com.compuserve.gif` raw bytes ride along as a
/// fallback for apps that paste inline image data and honor the GIF UTI (Mail).
/// We deliberately do NOT write a TIFF/PNG still — that's exactly the static
/// frame Chromium was grabbing.
@MainActor
enum GifClipboard {
    /// Fetches the GIF bytes from `url` and writes them to the pasteboard.
    /// `name` (the search query) flavors the staged filename a chat app shows
    /// on upload, e.g. `giphy-fire.gif`. Returns true on success.
    static func copy(from url: URL, name: String) async -> Bool {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return write(data: data, name: name)
        } catch {
            return false
        }
    }

    static func write(data: Data, name: String) -> Bool {
        guard let fileURL = stageTempFile(data: data, name: name) else { return false }

        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        // File URL first — the representation chat apps upload + animate.
        item.setString(fileURL.absoluteString, forType: .fileURL)
        // Raw GIF bytes for inline-image receivers that honor the GIF UTI.
        item.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
        // Tell clipboard managers not to record this transient write.
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        return pb.writeObjects([item])
    }

    /// Writes the GIF to a temp file we can hand off as a file URL. Receivers
    /// may read the file asynchronously after the paste, so we don't delete it
    /// immediately — instead we sweep stale pastes on the way in. Each paste
    /// gets its own subdir so the readable, non-unique filename can't clobber
    /// an earlier paste of a different GIF that a chat app is still uploading.
    /// Returns nil if staging fails.
    private static func stageTempFile(data: Data, name: String) -> URL? {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Mojito-GIFs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            sweepStaleEntries(in: root)
            let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let slug = safeFileBase(name)
            let fileName = slug.isEmpty ? "giphy.gif" : "giphy-\(slug).gif"
            let fileURL = dir.appendingPathComponent(fileName)
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    /// Turns the search query into a safe, readable filename fragment: keep
    /// alphanumerics, collapse every other run to a single `-`, trim, cap
    /// length. May return "" (caller falls back to a bare `giphy.gif`).
    private static func safeFileBase(_ name: String) -> String {
        var out = ""
        var lastWasDash = false
        for ch in name.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "_" {
                out.append(ch)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return String(trimmed.prefix(60))
    }

    /// Deletes staged pastes older than a few minutes — long enough that a
    /// recent paste's receiver has surely finished reading, short enough that
    /// the temp dir doesn't grow without bound across a session.
    private static func sweepStaleEntries(in dir: URL) {
        let cutoff = Date(timeIntervalSinceNow: -300)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for url in entries {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
