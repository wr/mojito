import Foundation

/// Decoded result row from a Giphy search.
struct GifAsset: Identifiable, Hashable {
    let id: String
    /// Animated thumbnail URL — small, cheap to load (100px tall).
    let thumbURL: URL
    /// Full-size animated URL — what we copy to the clipboard.
    let originalURL: URL
    /// Title text shown for accessibility / tooltip.
    let title: String

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String,
              let images = json["images"] as? [String: Any],
              let thumb = (images["fixed_height_small"] as? [String: Any])
                          ?? (images["fixed_height"] as? [String: Any]),
              let thumbStr = thumb["url"] as? String,
              let thumbURL = URL(string: thumbStr),
              let original = images["original"] as? [String: Any],
              let originalStr = original["url"] as? String,
              let originalURL = URL(string: originalStr)
        else { return nil }
        self.id = id
        self.thumbURL = thumbURL
        self.originalURL = originalURL
        self.title = (json["title"] as? String) ?? ""
    }
}
