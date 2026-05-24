import Foundation
import Combine

@MainActor
final class ExclusionStore: ObservableObject {
    static let shared = ExclusionStore()

    @Published var bundleIDs: Set<String>
    @Published var urlPatterns: Set<String>

    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    /// Compiled regex cache for URL patterns containing `*`. Keyed by the
    /// (lowercased) pattern; rebuilt only when urlPatterns changes. Avoids
    /// recompiling per-`:` keystroke during isExcluded().
    private var compiledPatterns: [String: NSRegularExpression] = [:]

    private init() {
        let initialBundles: Set<String>
        if let raw = defaults.array(forKey: PrefsKey.excludedBundleIDs) as? [String] {
            initialBundles = Set(raw)
        } else {
            initialBundles = Set(DefaultExclusions.bundleIDs)
            defaults.set(Array(initialBundles), forKey: PrefsKey.excludedBundleIDs)
        }
        bundleIDs = initialBundles

        let initialURLs: Set<String>
        if let raw = defaults.array(forKey: PrefsKey.excludedURLPatterns) as? [String] {
            initialURLs = Set(raw)
        } else {
            initialURLs = Set(DefaultExclusions.urlPatterns)
            defaults.set(Array(initialURLs), forKey: PrefsKey.excludedURLPatterns)
        }
        urlPatterns = initialURLs

        $bundleIDs
            .dropFirst()
            .sink { [weak self] in self?.defaults.set(Array($0), forKey: PrefsKey.excludedBundleIDs) }
            .store(in: &cancellables)

        // Build the pattern cache from the initial set first, then watch for
        // changes. The `.dropFirst()` skips the synthetic emit Combine sends
        // on subscribe — without it we'd rebuild the cache twice on launch.
        rebuildPatternCache(urlPatterns)
        $urlPatterns
            .dropFirst()
            .sink { [weak self] patterns in
                self?.defaults.set(Array(patterns), forKey: PrefsKey.excludedURLPatterns)
                self?.rebuildPatternCache(patterns)
            }
            .store(in: &cancellables)
    }

    private func rebuildPatternCache(_ patterns: Set<String>) {
        var built: [String: NSRegularExpression] = [:]
        for raw in patterns {
            let pattern = raw.lowercased()
            guard pattern.contains("*") else { continue }
            let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: "\\*", with: "[^.]+") + "$"
            if let regex = try? NSRegularExpression(pattern: regexPattern) {
                built[pattern] = regex
            }
        }
        compiledPatterns = built
    }

    func isExcluded(bundleID: String?, url: URL?) -> Bool {
        if let bundleID, bundleIDs.contains(bundleID) { return true }
        if let host = url?.host(percentEncoded: false)?.lowercased() {
            for pattern in urlPatterns where matches(host: host, pattern: pattern.lowercased()) {
                return true
            }
        }
        return false
    }

    func resetToDefaults() {
        bundleIDs = Set(DefaultExclusions.bundleIDs)
        urlPatterns = Set(DefaultExclusions.urlPatterns)
    }

    /// Glob match: `*` matches any subdomain segment. Compiled regexes are
    /// cached in `compiledPatterns` so this is a dictionary lookup per call.
    private func matches(host: String, pattern: String) -> Bool {
        if !pattern.contains("*") { return host == pattern }
        guard let regex = compiledPatterns[pattern] else { return false }
        let range = NSRange(host.startIndex..., in: host)
        return regex.firstMatch(in: host, range: range) != nil
    }
}
