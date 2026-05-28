import Foundation
import Combine

@MainActor
final class ExclusionStore: ObservableObject {
    static let shared = ExclusionStore()

    @Published var bundleIDs: Set<String>
    @Published var urlPatterns: Set<String>

    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    /// Rebuilt when urlPatterns changes so isExcluded() doesn't recompile per `:`.
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

        // `.dropFirst()` below skips Combine's synthetic on-subscribe emit
        // so the cache rebuilds once at launch, not twice.
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
            if let regex = Self.compiledGlob(for: pattern) {
                built[pattern] = regex
            }
        }
        compiledPatterns = built
    }

    /// Compile a wildcard host pattern. `*` matches exactly one subdomain
    /// segment (`[^.]+`), anchored at both ends. Returns nil for patterns
    /// with no wildcard — those are compared by equality.
    nonisolated static func compiledGlob(for pattern: String) -> NSRegularExpression? {
        guard pattern.contains("*") else { return nil }
        let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: "[^.]+") + "$"
        return try? NSRegularExpression(pattern: regexPattern)
    }

    /// Pure host/pattern decision. Equality unless the pattern carries a
    /// `*` wildcard. Compiles on demand — the instance hot path uses the
    /// `compiledPatterns` cache instead to avoid per-`:` recompilation.
    nonisolated static func matches(host: String, pattern: String) -> Bool {
        guard pattern.contains("*") else { return host == pattern }
        guard let regex = compiledGlob(for: pattern) else { return false }
        let range = NSRange(host.startIndex..., in: host)
        return regex.firstMatch(in: host, range: range) != nil
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

    /// `*` matches any single subdomain segment.
    private func matches(host: String, pattern: String) -> Bool {
        if !pattern.contains("*") { return host == pattern }
        guard let regex = compiledPatterns[pattern] else { return false }
        let range = NSRange(host.startIndex..., in: host)
        return regex.firstMatch(in: host, range: range) != nil
    }
}
