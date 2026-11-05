import Foundation

/// One GIF search result, independent of which provider returned it.
struct GifAsset: Identifiable, Hashable {
    let id: String
    /// Animated thumbnail URL — small, cheap to load (~90px tall).
    let thumbURL: URL
    /// Full-size animated URL — what we copy to the clipboard.
    let originalURL: URL
    /// Title text shown for accessibility / tooltip.
    let title: String
}

extension GifAsset {
    /// GIPHY: `fixed_height_small` (100px tall) for the grid. For the paste,
    /// `downsized_medium` (capped at 5 MB) before `original`, which can run
    /// far larger.
    init?(giphyJSON json: [String: Any]) {
        guard let id = json["id"] as? String,
              let images = json["images"] as? [String: Any]
        else { return nil }

        func rendition(_ name: String) -> URL? {
            guard let entry = images[name] as? [String: Any],
                  let str = entry["url"] as? String, !str.isEmpty
            else { return nil }
            return URL(string: str)
        }

        guard let thumb = rendition("fixed_height_small") ?? rendition("fixed_height"),
              let original = rendition("downsized_medium") ?? rendition("original")
        else { return nil }
        self.init(id: id, thumbURL: thumb, originalURL: original,
                  title: (json["title"] as? String) ?? "")
    }

    /// KLIPY ships `xs`/`sm`/`md`/`hd` renditions. `xs` (~90px tall) keeps a
    /// page of thumbnails light. For the paste, `hd` runs past 10 MB and `md`
    /// is sometimes the larger of the two, so take whichever file is smaller.
    init?(klipyJSON json: [String: Any]) {
        guard let slug = json["slug"] as? String,
              let file = json["file"] as? [String: Any]
        else { return nil }

        func rendition(_ size: String) -> (url: URL, bytes: Int)? {
            guard let entry = file[size] as? [String: Any],
                  let gif = entry["gif"] as? [String: Any],
                  let str = gif["url"] as? String,
                  let url = URL(string: str)
            else { return nil }
            return (url, (gif["size"] as? Int) ?? .max)
        }

        let pasteCandidates = [rendition("md"), rendition("hd")].compactMap { $0 }
        guard let thumb = rendition("xs") ?? rendition("sm") ?? rendition("md"),
              let original = pasteCandidates.min(by: { $0.bytes < $1.bytes })
        else { return nil }
        self.init(id: slug, thumbURL: thumb.url, originalURL: original.url,
                  title: (json["title"] as? String) ?? "")
    }
}
