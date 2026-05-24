import AppKit

/// "Mojito" in the release bundle, "Mojito Dev" in Debug — user-facing
/// copy stays accurate without per-site `#if DEBUG`.
enum AppInfo {
    static let displayName: String = {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Mojito"
    }()

    /// Loaded straight off disk — `NSWorkspace.icon(forFile:)` hits
    /// LaunchServices' icon cache, which lags behind bundle icon changes.
    static let appIcon: NSImage? = {
        let name = (Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String) ?? "AppIcon"
        guard let url = Bundle.main.url(forResource: name, withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }()
}
