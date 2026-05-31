import Combine
import Foundation

/// How the Quick Access pill is summoned. The Engine reads this from
/// `PrefsKey.favoritesTrigger`.
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

/// What the trigger surfaces — the compact pill or the full browser grid.
enum FavoritesTriggerSurface: String, CaseIterable, Identifiable {
    case pill
    case browser

    var id: String { rawValue }

    var settingsLabel: String {
        switch self {
        case .pill:    return String(localized: "Quick access pill")
        case .browser: return String(localized: "Full emoji browser")
        }
    }

    static func from(_ raw: String?) -> FavoritesTriggerSurface {
        raw.flatMap(FavoritesTriggerSurface.init(rawValue:)) ?? .pill
    }
}

/// The bare-`:` Quick Access row: a fixed set of 8 slots, each either **auto**
/// (filled from most-used) or **pinned** to a specific emoji. Persisted as an
/// 8-element `[String]` where `""` marks an auto slot.
@MainActor
final class QuickAccessStore: ObservableObject {
    static let shared = QuickAccessStore()
    static let slotCount = 8

    /// One entry per slot: `nil` = auto, else a pinned hexcode.
    @Published private(set) var slots: [String?]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = (defaults.array(forKey: PrefsKey.quickAccessSlots) as? [String]) ?? []
        var parsed: [String?] = raw.map { $0.isEmpty ? nil : $0 }
        if parsed.count < Self.slotCount {
            parsed += Array(repeating: nil, count: Self.slotCount - parsed.count)
        }
        self.slots = Array(parsed.prefix(Self.slotCount))
    }

    /// Pin `hexcode` to `index`, clearing it from any other slot so a glyph
    /// never occupies two slots.
    func pin(_ hexcode: String, at index: Int) {
        guard slots.indices.contains(index) else { return }
        for i in slots.indices where slots[i] == hexcode { slots[i] = nil }
        slots[index] = hexcode
        persist()
    }

    /// Reset a single slot back to auto (most-used).
    func reset(at index: Int) {
        guard slots.indices.contains(index), slots[index] != nil else { return }
        slots[index] = nil
        persist()
    }

    func resetAll() {
        guard hasPins else { return }
        slots = Array(repeating: nil, count: Self.slotCount)
        persist()
    }

    var hasPins: Bool { slots.contains { $0 != nil } }

    private func persist() {
        defaults.set(slots.map { $0 ?? "" }, forKey: PrefsKey.quickAccessSlots)
    }
}

/// One resolved Quick Access slot for display: the emoji that fills it (if
/// any) and whether the user pinned it.
struct ResolvedSlot {
    let emoji: Emoji?
    let pinned: Bool
}

/// Resolves the Quick Access slots to concrete emoji: pinned slots show their
/// emoji; auto slots fill, in slot order, from most-used (skipping symbols,
/// pinned glyphs, and anything already shown).
@MainActor
enum QuickAccess {
    static func resolvedPerSlot(
        store: QuickAccessStore,
        database: EmojiDatabase,
        usage: [String: Int]
    ) -> [ResolvedSlot] {
        let pinned = Set(store.slots.compactMap { $0 })
        var pool = usage
            .filter { $0.value > 0 && !$0.key.hasPrefix("SYM_") && !pinned.contains($0.key) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)
            .makeIterator()
        var used = pinned
        var out: [ResolvedSlot] = []
        for slot in store.slots {
            if let hex = slot {
                out.append(ResolvedSlot(emoji: database.byHexcode[hex], pinned: true))
            } else {
                var fill: Emoji?
                while let hex = pool.next() {
                    guard !used.contains(hex), let emoji = database.byHexcode[hex] else { continue }
                    used.insert(hex)
                    fill = emoji
                    break
                }
                out.append(ResolvedSlot(emoji: fill, pinned: false))
            }
        }
        return out
    }

    /// Flat list of the resolved emoji (drops empty auto slots) — the bare-`:`
    /// pill corpus and the browser's Quick Access section.
    static func resolved(
        store: QuickAccessStore,
        database: EmojiDatabase,
        usage: [String: Int]
    ) -> [Emoji] {
        resolvedPerSlot(store: store, database: database, usage: usage).compactMap(\.emoji)
    }
}
