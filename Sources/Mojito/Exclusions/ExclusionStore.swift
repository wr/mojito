import Foundation
import Combine

enum ExclusionMode: String {
    case denylist
    case allowlist
}

@MainActor
final class ExclusionStore: ObservableObject {
    static let shared = ExclusionStore()

    @Published var mode: ExclusionMode
    @Published var bundleIDs: Set<String>
    @Published var urlPatterns: Set<String>
    /// Active lists when `mode == .allowlist`. Kept separate from the deny
    /// lists so flipping the mode doesn't repurpose the default denylist
    /// (Slack, Discord, Notion…) as the user's allowlist.
    @Published var allowedBundleIDs: Set<String>
    @Published var allowedURLPatterns: Set<String>

    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    /// Rebuilt when urlPatterns changes so isExcluded() doesn't recompile per `:`.
    private var compiledPatterns: [String: NSRegularExpression] = [:]

    private init() {
        if let raw = defaults.string(forKey: PrefsKey.exclusionMode),
           let parsed = ExclusionMode(rawValue: raw) {
            mode = parsed
        } else {
            mode = .denylist
        }

        var initialBundles: Set<String>
        if let raw = defaults.array(forKey: PrefsKey.excludedBundleIDs) as? [String] {
            initialBundles = Set(raw)
        } else {
            initialBundles = Set(DefaultExclusions.bundleIDs)
            defaults.set(Array(initialBundles), forKey: PrefsKey.excludedBundleIDs)
        }
        // One-time, additive: fold the developer-tool defaults into existing
        // installs (new installs already got them via the seed above). Guarded
        // so any of these a user later removes won't reappear. No-op for
        // allowlist-mode users until they switch back to a denylist.
        if !defaults.bool(forKey: PrefsKey.devToolExclusionsSeeded) {
            let merged = initialBundles.union(DefaultExclusions.developerTools)
            if merged != initialBundles {
                initialBundles = merged
                defaults.set(Array(initialBundles), forKey: PrefsKey.excludedBundleIDs)
            }
            defaults.set(true, forKey: PrefsKey.devToolExclusionsSeeded)
        }
        bundleIDs = initialBundles

        let initialAllowed: Set<String>
        if let raw = defaults.array(forKey: PrefsKey.allowedBundleIDs) as? [String] {
            initialAllowed = Set(raw)
        } else {
            initialAllowed = []
        }
        allowedBundleIDs = initialAllowed

        let initialURLs: Set<String>
        if let raw = defaults.array(forKey: PrefsKey.excludedURLPatterns) as? [String] {
            initialURLs = Set(raw)
        } else {
            initialURLs = Set(DefaultExclusions.urlPatterns)
            defaults.set(Array(initialURLs), forKey: PrefsKey.excludedURLPatterns)
        }
        urlPatterns = initialURLs

        let initialAllowedURLs: Set<String>
        if let raw = defaults.array(forKey: PrefsKey.allowedURLPatterns) as? [String] {
            initialAllowedURLs = Set(raw)
        } else {
            initialAllowedURLs = []
        }
        allowedURLPatterns = initialAllowedURLs

        $mode
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0.rawValue, forKey: PrefsKey.exclusionMode) }
            .store(in: &cancellables)

        $bundleIDs
            .dropFirst()
            .sink { [weak self] in self?.defaults.set(Array($0), forKey: PrefsKey.excludedBundleIDs) }
            .store(in: &cancellables)

        $allowedBundleIDs
            .dropFirst()
            .sink { [weak self] in self?.defaults.set(Array($0), forKey: PrefsKey.allowedBundleIDs) }
            .store(in: &cancellables)

        // `.dropFirst()` below skips Combine's synthetic on-subscribe emit
        // so the cache rebuilds once at launch, not twice.
        rebuildPatternCache(urlPatterns.union(allowedURLPatterns))
        // `@Published` fires in willSet, so inside each sink the *other*
        // set's `self` value is still current while the changed set arrives
        // as the closure argument — union them to rebuild the shared cache.
        $urlPatterns
            .dropFirst()
            .sink { [weak self] patterns in
                guard let self else { return }
                self.defaults.set(Array(patterns), forKey: PrefsKey.excludedURLPatterns)
                self.rebuildPatternCache(patterns.union(self.allowedURLPatterns))
            }
            .store(in: &cancellables)
        $allowedURLPatterns
            .dropFirst()
            .sink { [weak self] patterns in
                guard let self else { return }
                self.defaults.set(Array(patterns), forKey: PrefsKey.allowedURLPatterns)
                self.rebuildPatternCache(self.urlPatterns.union(patterns))
            }
            .store(in: &cancellables)
    }

    /// Cache is keyed by pattern string, so one dictionary covers both the
    /// deny and allow lists; whichever set is active at match time picks
    /// which keys to consult.
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

    /// Pure host/pattern decision. A wildcard pattern goes through the regex;
    /// a plain pattern matches the domain itself or any subdomain of it
    /// (label-boundary suffix), so `google.com` covers `mail.google.com` but
    /// not `notgoogle.com`. Compiles on demand — the instance hot path uses
    /// the `compiledPatterns` cache instead to avoid per-`:` recompilation.
    nonisolated static func matches(host: String, pattern: String) -> Bool {
        guard pattern.contains("*") else { return hostMatchesDomain(host, pattern) }
        guard let regex = compiledGlob(for: pattern) else { return false }
        let range = NSRange(host.startIndex..., in: host)
        return regex.firstMatch(in: host, range: range) != nil
    }

    /// A plain (non-wildcard) pattern matches its apex and every subdomain.
    /// The leading `.` on the suffix check keeps the match on a label
    /// boundary — `notgoogle.com` shares the `google.com` suffix but isn't a
    /// subdomain, so it must not match.
    nonisolated static func hostMatchesDomain(_ host: String, _ pattern: String) -> Bool {
        host == pattern || host.hasSuffix("." + pattern)
    }

    func isExcluded(bundleID: String?, url: URL?) -> Bool {
        switch mode {
        case .denylist:
            if let bundleID, bundleIDs.contains(bundleID) { return true }
            if let host = url?.host(percentEncoded: false)?.lowercased() {
                for pattern in urlPatterns where matches(host: host, pattern: pattern.lowercased()) {
                    return true
                }
            }
            return false
        case .allowlist:
            // Allow if the app is allowlisted, OR if the focused URL matches
            // an allowed site — the latter implicitly allows whatever browser
            // is hosting it, so users don't have to allowlist Chrome to allow
            // github.com. Everything else is blocked.
            if let bundleID, allowedBundleIDs.contains(bundleID) { return false }
            if let host = url?.host(percentEncoded: false)?.lowercased() {
                for pattern in allowedURLPatterns where matches(host: host, pattern: pattern.lowercased()) {
                    return false
                }
            }
            return true
        }
    }

    func resetToDefaults() {
        mode = .denylist
        bundleIDs = Set(DefaultExclusions.bundleIDs)
        allowedBundleIDs = []
        urlPatterns = Set(DefaultExclusions.urlPatterns)
        allowedURLPatterns = []
    }

    /// `*` matches any single subdomain segment; a plain pattern matches the
    /// domain and its subdomains (see `hostMatchesDomain`).
    private func matches(host: String, pattern: String) -> Bool {
        if !pattern.contains("*") { return Self.hostMatchesDomain(host, pattern) }
        guard let regex = compiledPatterns[pattern] else { return false }
        let range = NSRange(host.startIndex..., in: host)
        return regex.firstMatch(in: host, range: range) != nil
    }
}
