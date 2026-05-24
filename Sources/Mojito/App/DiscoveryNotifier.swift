import Foundation
import UserNotifications

/// Notifies on first discovery of each egg. Permission requested lazily
/// on the first call; denial silences future notifications (visual
/// effect still runs — this is purely additive).
@MainActor
enum DiscoveryNotifier {
    static func notify(_ egg: EasterEgg) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { post(egg) }
                    }
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { post(egg) }
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private static func post(_ egg: EasterEgg) {
        let content = UNMutableNotificationContent()
        content.title = "Easter egg discovered"
        content.body = egg.title
        let total = EasterEggTracker.totalCount
        let count = EasterEggTracker.discoveredCount
        if count < total {
            content.subtitle = "\(count) of \(total)"
        } else {
            content.subtitle = "All \(total) found"
        }
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "mojito.eggDiscovered.\(egg.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
