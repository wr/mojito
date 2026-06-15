import Foundation

/// Two user-facing toggles gate easter-egg audio; the visuals always run.
/// `discoveryFanfareEnabled` controls the "egg found" chime
/// (`DiscoveryFanfare`); `effectSoundsEnabled` controls the sound an
/// individual egg makes while it runs. Both default on when the key is
/// absent, so existing installs keep their current (audible) behavior.
@MainActor
enum EggSound {
    static var discoveryFanfareEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefsKey.eggDiscoverySoundEnabled) as? Bool ?? true
    }

    static var effectSoundsEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefsKey.eggEffectSoundsEnabled) as? Bool ?? true
    }
}
