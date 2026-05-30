import Combine
import Foundation

/// How the favorites/most-used pill is summoned.
enum FavoritesTrigger: String, CaseIterable, Identifiable {
    /// Never auto-shown (the pill only ever appears via the menu/browser).
    case off
    /// A bare `:` that dwells ~¼s.
    case colon
    /// An explicit `:?` (the `?` is swallowed).
    case question

    var id: String { rawValue }

    var settingsLabel: String {
        switch self {
        case .off:      return String(localized: "Off")
        case .colon:    return String(localized: "When I type “:” and pause")
        case .question: return String(localized: "When I type “:?”")
        }
    }

    static func from(_ raw: String?) -> FavoritesTrigger {
        raw.flatMap(FavoritesTrigger.init(rawValue:)) ?? .question
    }
}

/// Ordered list of hand-picked favorite emoji (by hexcode). Surfaced when
/// the user types a bare `:` and managed in Settings ▸ Favorites. Mirrors
/// `ExclusionStore`'s shape: a `@Published` model that mirrors itself into
/// UserDefaults on every mutation, so the Engine and the Settings pane read
/// the same live source.
@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var hexcodes: [String]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hexcodes = (defaults.array(forKey: PrefsKey.favoriteHexcodes) as? [String]) ?? []
    }

    func isFavorite(_ hexcode: String) -> Bool {
        hexcodes.contains(hexcode)
    }

    func toggle(_ hexcode: String) {
        isFavorite(hexcode) ? remove(hexcode) : add(hexcode)
    }

    func add(_ hexcode: String) {
        guard !hexcodes.contains(hexcode) else { return }
        hexcodes.append(hexcode)
        persist()
    }

    func remove(_ hexcode: String) {
        guard hexcodes.contains(hexcode) else { return }
        hexcodes.removeAll { $0 == hexcode }
        persist()
    }

    /// Reorder. Matches SwiftUI's `onMove` contract without pulling SwiftUI
    /// into the model layer: pull the moved items out, then splice them back
    /// at `toOffset` adjusted for any removed items ahead of it.
    func move(fromOffsets: IndexSet, toOffset: Int) {
        let moved = fromOffsets.sorted().map { hexcodes[$0] }
        let removedBefore = fromOffsets.filter { $0 < toOffset }.count
        var next = hexcodes
        for index in fromOffsets.sorted(by: >) { next.remove(at: index) }
        next.insert(contentsOf: moved, at: toOffset - removedBefore)
        hexcodes = next
        persist()
    }

    func clear() {
        guard !hexcodes.isEmpty else { return }
        hexcodes.removeAll()
        persist()
    }

    private func persist() {
        defaults.set(hexcodes, forKey: PrefsKey.favoriteHexcodes)
    }
}
