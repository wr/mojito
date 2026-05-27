import AppKit
import SwiftUI

/// Renders an animated GIF from a remote URL. SwiftUI's `Image`/`AsyncImage`
/// only show the first frame, so we bridge to AppKit's `NSImageView` —
/// `NSImage(data:)` decodes animated GIFs natively, and `animates = true`
/// runs the playback.
struct AnimatedGifView: NSViewRepresentable {
    let url: URL?
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.animates = true
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.canDrawSubviewsIntoLayer = true
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
        guard let url else {
            nsView.image = nil
            return
        }
        // Cancel any prior task and kick a new fetch tied to this URL.
        context.coordinator.load(url: url, into: nsView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private var currentURL: URL?
        private var task: URLSessionDataTask?

        func load(url: URL, into view: NSImageView) {
            if currentURL == url, view.image != nil { return }
            currentURL = url
            task?.cancel()
            view.image = nil

            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
            task = URLSession.shared.dataTask(with: request) { [weak view] data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { [weak view] in
                    guard let view else { return }
                    view.image = image
                    // `animates` resets when `image` is reassigned on some
                    // macOS versions — set it again to be safe.
                    view.animates = true
                }
            }
            task?.resume()
        }
    }
}
