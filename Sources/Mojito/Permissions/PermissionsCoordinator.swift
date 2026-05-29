import AppKit
import ApplicationServices
import Combine
import IOKit.hid

@MainActor
final class PermissionsCoordinator: ObservableObject {
    @Published private(set) var accessibility = false
    @Published private(set) var inputMonitoring = false

    private var timer: Timer?
    private var distributedObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?

    init() {
        refresh()
        // System posts this when an app's Accessibility status changes —
        // lets us react instantly instead of waiting for the next poll.
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification fires slightly before the AX subsystem
            // flips, so refresh now AND a moment later.
            self?.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.refresh() }
        }
        // Changing an Accessibility grant means switching to System Settings
        // and back. The trust state can lag a live toggle, so re-derive it
        // whenever we regain focus — by then the change has settled.
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
        }
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    /// AX uses the distributed notification, so this timer is really
    /// just for catching Input Monitoring toggles. 5s is slow enough not
    /// to churn IPC but fast enough for a quick green checkmark.
    private static let slowPollInterval: TimeInterval = 5.0

    func startMonitoring(interval: TimeInterval = slowPollInterval) {
        refresh()
        // Stop polling once granted; revocation re-enters via
        // `handleInputMonitoringLost()`.
        if allGranted {
            stopMonitoring()
            return
        }
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let ax = AXIsProcessTrusted()
        let im = checkInputMonitoring()
        if ax != accessibility {
            accessibility = ax
            DebugRecorder.record(.permissions, ax ? "axGranted" : "axRevoked")
        }
        if im != inputMonitoring {
            inputMonitoring = im
            DebugRecorder.record(.permissions, im ? "inputGranted" : "inputRevoked")
        }
        if accessibility && inputMonitoring {
            stopMonitoring()
        }
    }

    /// `IOHIDCheckAccess` is cheap and idempotent. `CGEvent.tapCreate` as
    /// a probe would fire the system Input Monitoring alert before our
    /// onboarding can introduce it — `promptInputMonitoring()` is the
    /// only sanctioned entry point.
    private func checkInputMonitoring() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Called when the KeyMonitor tap dies (user revoked Input Monitoring).
    func handleInputMonitoringLost() {
        inputMonitoring = false
        startMonitoring()
    }

    var allGranted: Bool { accessibility && inputMonitoring }

    /// Fires the system prompt the first time. Returns true if already
    /// trusted, false otherwise.
    @discardableResult
    func promptAccessibility() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: kCFBooleanTrue!] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func promptInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
