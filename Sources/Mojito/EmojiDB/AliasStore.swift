import Foundation

/// One user-defined shortcode → emoji mapping. `alias` is stored normalized
/// (lowercased, trimmed, no whitespace/colons) so lookups never re-process it.
struct CustomAlias: Codable, Identifiable, Hashable {
    let alias: String
    let hexcode: String
    var id: String { alias }
}

/// The user's custom shortcodes. Persisted as a JSON blob and merged into the
/// emoji corpus by `EmojiDatabase` — see [[EmojiDatabase.buildIndex]]. A change
/// posts `didChangeNotification`, which `EmojiDatabase` observes to rebuild its
/// index live.
@MainActor
final class AliasStore: ObservableObject {
    static let shared = AliasStore()

    /// Posted after any mutation persists. `EmojiDatabase` observes this to
    /// re-merge aliases into its search index without a relaunch.
    static let didChangeNotification = Notification.Name("mojito.aliases.didChange")

    /// Order-preserving so the settings list is stable across edits.
    @Published private(set) var aliases: [CustomAlias]

    private let defaults: UserDefaults

    /// A hand-typed alias longer than this can't realistically be typed before
    /// the capture times out — reject rather than store an unreachable entry.
    static let maxLength = 40

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: PrefsKey.customAliases),
           let decoded = try? JSONDecoder().decode([CustomAlias].self, from: data) {
            aliases = AliasStore.sanitize(decoded)
        } else {
            aliases = []
        }
    }

    enum AddResult: Equatable {
        case added        // new alias stored
        case updated      // existing alias re-pointed at a different emoji
        case invalid      // alias text or hexcode rejected
    }

    /// Add or re-point an alias. Adding an alias that already exists updates its
    /// target (`.updated`); the alias keeps its position in the list.
    @discardableResult
    func add(alias raw: String, hexcode: String) -> AddResult {
        guard let normalized = AliasStore.normalize(raw), !hexcode.isEmpty else { return .invalid }
        let entry = CustomAlias(alias: normalized, hexcode: hexcode)
        if let idx = aliases.firstIndex(where: { $0.alias == normalized }) {
            guard aliases[idx] != entry else { return .updated }
            aliases[idx] = entry
            persist()
            return .updated
        }
        aliases.append(entry)
        persist()
        return .added
    }

    func remove(alias raw: String) {
        guard let normalized = AliasStore.normalize(raw) else { return }
        let before = aliases.count
        aliases.removeAll { $0.alias == normalized }
        if aliases.count != before { persist() }
    }

    func removeAll() {
        guard !aliases.isEmpty else { return }
        aliases.removeAll()
        persist()
    }

    func contains(alias raw: String) -> Bool {
        guard let normalized = AliasStore.normalize(raw) else { return false }
        return aliases.contains { $0.alias == normalized }
    }

    // MARK: - Validation

    /// Canonical form for an alias, or `nil` if it can't be a usable shortcode.
    /// Rejected: empty, over `maxLength`, or containing any character the trigger
    /// can't capture as part of a name — whitespace, `:`, `.`, `/`, emoji, etc.
    /// all end capture, so such an alias could never be typed in full.
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        // Mirror KeyMonitor.isNameChar: letters, numbers, and _ - + ' are the
        // only characters the capture state machine keeps in the query body.
        guard trimmed.allSatisfy(isNameChar) else { return nil }
        return trimmed
    }

    private static func isNameChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "-" || c == "+" || c == "'"
    }

    /// Drop invalid or duplicate entries from a decoded blob (hand-edits, older
    /// formats) so a corrupt store can't poison the index. First spelling wins.
    static func sanitize(_ decoded: [CustomAlias]) -> [CustomAlias] {
        var seen: Set<String> = []
        var out: [CustomAlias] = []
        for entry in decoded {
            guard let normalized = normalize(entry.alias), !entry.hexcode.isEmpty else { continue }
            guard seen.insert(normalized).inserted else { continue }
            out.append(CustomAlias(alias: normalized, hexcode: entry.hexcode))
        }
        return out
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(aliases) {
            defaults.set(data, forKey: PrefsKey.customAliases)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
