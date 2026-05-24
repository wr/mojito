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

    init() {
        refresh()
        // System posts this distributed notification when an app's Accessibility status changes.
        // Listening lets us react instantly instead of waiting for the next poll tick.
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The TCC change is posted slightly before AXIsProcessTrusted() returns true, so
            // refresh now AND a moment later.
            self?.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.refresh() }
        }
    }

    deinit {
        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
        }
    }

    /// Default polling interval while permissions are missing. Slow enough that the
    /// background `CGEvent.tapCreate` probe doesn't show up as constant IPC churn,
    /// fast enough that the user sees a green checkmark within a few seconds of
    /// granting permission. AX changes are picked up instantly via the
    /// `com.apple.accessibility.api` distributed notification anyway, so the timer
    /// is really only there to catch Input Monitoring toggles.
    private static let slowPollInterval: TimeInterval = 5.0

    func startMonitoring(interval: TimeInterval = slowPollInterval) {
        refresh()
        // Once both permissions are granted, stop polling entirely. AX flips arrive
        // via the distributed notification; Input Monitoring revocation surfaces
        // through the real KeyMonitor tap's `tapDisabledByUserInput` callback, which
        // routes back into `handleInputMonitoringLost()` to restart polling.
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
        if ax != accessibility { accessibility = ax }
        if im != inputMonitoring { inputMonitoring = im }
        // Stop polling the moment both come back true — flip to event-driven mode.
        // (`startMonitoring` is the entry point when we need to start polling again,
        // e.g. on revocation.)
        if accessibility && inputMonitoring {
            stopMonitoring()
        }
    }

    /// Cheap, idempotent Input Monitoring liveness check. Always uses
    /// `IOHIDCheckAccess` — calling `CGEvent.tapCreate` as a probe on first launch
    /// triggers the system Input Monitoring alert before onboarding has a chance to
    /// introduce it (you see the OS dialog instead of our welcome screen).
    /// `promptInputMonitoring()` is the only sanctioned entry point for the prompt.
    private func checkInputMonitoring() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Called by the engine when the real KeyMonitor's event tap gets disabled by the
    /// system (revocation, user toggling Input Monitoring off, etc). Resumes polling
    /// until permissions come back.
    func handleInputMonitoringLost() {
        inputMonitoring = false
        startMonitoring()
    }

    var allGranted: Bool { accessibility && inputMonitoring }

    /// Trigger the system "wants to control accessibility" prompt. Only fires the first time.
    /// Returns true if already trusted, false if the prompt was shown (or had been dismissed before).
    @discardableResult
    func promptAccessibility() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: kCFBooleanTrue!] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Trigger the system Input Monitoring prompt the first time it's called.
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
