import AppKit
import ApplicationServices
import Combine
import KeyboardShortcuts
import os.log
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let permissions = PermissionsCoordinator()
    let exclusions = ExclusionStore.shared
    let database = EmojiDatabase.shared
    let engine: Engine

    private let log = OSLog(subsystem: "ee.wells.Mojito", category: "AppDelegate")
    private let menuBar = MenuBarController()
    private let onboardingController = OnboardingWindowController()
    private let settingsController = SettingsWindowController()
    private var observers = Set<AnyCancellable>()

    override init() {
        engine = Engine(database: database, exclusions: exclusions)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        os_log("applicationDidFinishLaunching", log: log, type: .info)
        // SingleInstanceCoordinator queued a terminate() in main.swift if
        // we're yielding to a peer. Bail before doing anything expensive.
        if SingleInstanceCoordinator.shared.willQuitDueToPeer {
            os_log("Skipping launch setup; yielding to existing peer instance", log: log, type: .info)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        applyAppIcon()

        // Bound every AX query globally. Without this, a revoked Accessibility
        // grant (or a hung target app) makes synchronous AX calls on the
        // keystroke path block forever — and since the event-tap callback runs
        // on the main thread, that freezes the keyboard system-wide. Set on the
        // system-wide element, it's the default timeout for all AX messages.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)

        permissions.startMonitoring()
        engine.attach(permissions: permissions)
        // Start observing focus changes before the user types their first `:`.
        _ = FocusedElementCache.shared
        UpdaterCoordinator.shared.start()

        // About → Stats reads this for "User since".
        if UserDefaults.standard.object(forKey: PrefsKey.firstLaunchDate) == nil {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: PrefsKey.firstLaunchDate)
        }

        // Arrows were a sub-toggle of emoticons before v1.4: emoticons off
        // meant arrows implicitly off, and the hidden sub-toggle was never
        // written. Pin that state now that the toggles are independent, so
        // updating doesn't switch arrow conversion on behind anyone's back.
        // Self-limiting: a no-op once the arrow key holds any value.
        if UserDefaults.standard.object(forKey: PrefsKey.arrowConversionEnabled) == nil,
           (UserDefaults.standard.object(forKey: PrefsKey.emoticonsEnabled) as? Bool) == false {
            UserDefaults.standard.set(false, forKey: PrefsKey.arrowConversionEnabled)
        }

        // Anonymous, consent-gated daily stats. Self-gates — a no-op until the
        // user has seen the notice and left it enabled.
        TelemetryUploader.shared.uploadIfDue()
        scheduleTelemetryFlush()

        menuBar.install(
            engine: engine,
            permissions: permissions,
            openSettings: { [weak self] in self?.openSettings() }
        )

        if let until = UserDefaults.standard.object(forKey: PrefsKey.pausedUntil) as? TimeInterval {
            let date = Date(timeIntervalSince1970: until)
            if date > Date() { engine.pausedUntil = date }
        }

        // Carbon hotkeys via KeyboardShortcuts — independent of our
        // CGEventTap, so they still fire when Mojito is paused or Input
        // Monitoring is revoked.
        KeyboardShortcuts.onKeyDown(for: .pauseHour) { [weak self] in
            self?.toggleOrPause(until: Date().addingTimeInterval(3600))
        }
        KeyboardShortcuts.onKeyDown(for: .pauseUntilTomorrow) { [weak self] in
            self?.toggleOrPause(until: Self.tomorrowMorning())
        }
        KeyboardShortcuts.onKeyDown(for: .showEmojiBrowser) { [weak self] in
            self?.engine.toggleBrowser()
        }
        // Re-assert the runtime-only system-panel suppression (the ⌃⌘Space
        // binding and Fn pref persist on their own).
        SystemEmojiPickerReplacer.shared.applyAtLaunch()

        // Force onboarding any time permissions aren't granted — revoked
        // perms / fresh accounts get the guided fix, not a silent break.
        let needsOnboarding = !UserDefaults.standard.bool(forKey: PrefsKey.onboardingComplete)
            || !permissions.allGranted
        if needsOnboarding {
            openOnboarding()
        } else {
            engine.start()
            TelemetryConsent.presentIfNeeded()
        }

        NotificationCenter.default.publisher(for: .mojitoShouldShowOnboarding)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.openOnboarding() }
            .store(in: &observers)

        NotificationCenter.default.publisher(for: .mojitoOnboardingFinished)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.onboardingController.close()
                self?.engine.start()
                // Drop the onboarding fast-poll back to the baseline cadence.
                self?.permissions.startMonitoring()
                // First run reaches "running" here — surface the stats consent.
                TelemetryConsent.presentIfNeeded()
            }
            .store(in: &observers)

        NotificationCenter.default.publisher(for: .mojitoShouldOpenSettings)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.openSettings() }
            .store(in: &observers)

        NotificationCenter.default.publisher(for: .mojitoShouldOpenBrowser)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.engine.showBrowser() }
            .store(in: &observers)

        // Onboarding's Done step asks the engine to go live early so its
        // "try it out" field expands shortcuts. Idempotent — start() reconciles.
        NotificationCenter.default.publisher(for: .mojitoShouldStartEngine)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.engine.start() }
            .store(in: &observers)

        // Discovery banner click: open Settings, then ask the navigator to
        // reveal the egg. Order matters — open first so a fresh window's
        // views mount and pick up the (already-set) reveal request on appear.
        NotificationCenter.default.publisher(for: .mojitoRevealEasterEgg)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                self?.openSettings()
                if let id = note.object as? String {
                    SettingsNavigator.shared.revealEgg(id)
                }
            }
            .store(in: &observers)
    }

    func applicationWillTerminate(_ notification: Notification) {
        os_log("applicationWillTerminate", log: log, type: .info)
        // Best-effort send of this session's tail. The async POST may not
        // finish before the process exits, but the timer/day-change/wake
        // paths below are what actually keeps long-lived installs current.
        TelemetryUploader.shared.uploadIfDue()
    }

    /// `uploadIfDue()` used to fire only at launch, so a menu-bar app the user
    /// never quits would sit on a full day of pending deltas until its next
    /// relaunch — starving the public stats. Re-attempt on an hourly timer, at
    /// day rollover, and on wake. The uploader's once-per-UTC-day gate makes
    /// every extra call a cheap no-op, so this only ever sends real work once.
    private func scheduleTelemetryFlush() {
        Timer.publish(every: 3600, on: .main, in: .common)
            .autoconnect()
            .sink { _ in TelemetryUploader.shared.uploadIfDue() }
            .store(in: &observers)

        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: RunLoop.main)
            .sink { _ in TelemetryUploader.shared.uploadIfDue() }
            .store(in: &observers)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { _ in TelemetryUploader.shared.uploadIfDue() }
            .store(in: &observers)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Without this an `LSUIElement` app silently no-ops on relaunch from
    /// Finder/Dock/Spotlight, which feels broken. Show Settings (or
    /// onboarding if incomplete) so the click does something visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        let onboardingComplete = UserDefaults.standard.bool(forKey: PrefsKey.onboardingComplete)
        if onboardingComplete && permissions.allGranted {
            openSettings()
        } else {
            openOnboarding()
        }
        return false
    }

    func openOnboarding() {
        onboardingController.show(permissions: permissions)
    }

    func openSettings() {
        settingsController.show(permissions: permissions, exclusions: exclusions, engine: engine)
    }

    /// Bypasses LaunchServices' icon cache (lags behind bundle changes,
    /// most visible in the dev build's `AppIconDev` swap).
    private func applyAppIcon() {
        if let icon = AppInfo.appIcon {
            NSApp.applicationIconImage = icon
        }
    }

    private func toggleOrPause(until date: Date) {
        if let until = engine.pausedUntil, until > Date() {
            engine.resume()
        } else {
            engine.pause(until: date)
        }
    }

    private static func tomorrowMorning() -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.day = (components.day ?? 0) + 1
        components.hour = 7
        return Calendar.current.date(from: components) ?? Date().addingTimeInterval(8 * 3600)
    }

    /// `LSUIElement: true` apps don't get a default menu, so ⌘Q etc.
    /// won't fire from focused windows (onboarding, settings). Install a
    /// minimal one; the bar itself stays hidden via LSUIElement.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let appName = AppInfo.displayName
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Without these wired through, text fields don't get
        // standard copy/paste/select-all.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut",     action: #selector(NSText.cut(_:)),       keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",    action: #selector(NSText.copy(_:)),      keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",   action: #selector(NSText.paste(_:)),     keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
