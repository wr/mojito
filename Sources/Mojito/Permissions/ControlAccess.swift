import Foundation

/// How far macOS lets Mojito reach the keyboard and other apps.
enum ControlAccess: Equatable {
    case none
    /// Granted for chosen apps only (macOS 27.3 "Choose Apps"). The process
    /// reads as trusted and the key tap installs, but no keys reach the tap
    /// and posted keys are dropped.
    case limited
    /// Granted while running on a system with scoped grants. The post-event
    /// preflight doesn't update inside a live process, so limited and full
    /// can't be told apart until the next launch or the first key through
    /// the tap.
    case unverified
    case full

    var isUsable: Bool { self == .full || self == .unverified }

    /// macOS 27.3 split Accessibility into a per-app grant and a full one.
    static let systemHasScopedGrants: Bool = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 27, minorVersion: 3, patchVersion: 0)
    )

    /// - Parameters:
    ///   - launchReadingValid: the process was already trusted at launch and
    ///     the grant hasn't changed since, so `canPostAtLaunch` describes it.
    ///   - keysArriving: a real key has come through the event tap.
    static func resolve(
        trusted: Bool,
        scopedGrants: Bool,
        launchReadingValid: Bool,
        canPostAtLaunch: Bool,
        keysArriving: Bool
    ) -> ControlAccess {
        guard trusted else { return .none }
        guard scopedGrants else { return .full }
        if keysArriving { return .full }
        guard launchReadingValid else { return .unverified }
        return canPostAtLaunch ? .full : .limited
    }
}
