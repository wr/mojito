import AppKit

/// Runtime app metadata. The display name resolves from `CFBundleName` in the
/// running bundle — "Mojito" for the released app, "Mojito Dev" for the Debug
/// build — so user-facing copy stays accurate without per-config `#if DEBUG`
/// at every site.
enum AppInfo {
    static let displayName: String = {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Mojito"
    }()

    /// The bundle's icon loaded straight off disk via `CFBundleIconFile`.
    /// Going through `NSWorkspace.icon(forFile:)` hits LaunchServices' icon
    /// cache, which can lag behind when the bundle's icon changes (most
    /// visibly on the dev build's `AppIconDev` swap).
    static let appIcon: NSImage? = {
        let name = (Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String) ?? "AppIcon"
        guard let url = Bundle.main.url(forResource: name, withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }()
}
