import AppKit
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
        // SingleInstanceCoordinator.enforce() already ran in main.swift.
        // If it decided we should yield to a peer, the terminate() is
        // queued for the next runloop tick — bail before doing anything
        // expensive (engine wiring, AX permission polling, menu bar install).
        if SingleInstanceCoordinator.shared.willQuitDueToPeer {
            os_log("Skipping launch setup; yielding to existing peer instance", log: log, type: .info)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        applyAppIcon()

        permissions.startMonitoring()
        engine.attach(permissions: permissions)
        // Eagerly initialize the AX focus cache so we start observing focus
        // changes immediately, before the user types their first `:`.
        _ = FocusedElementCache.shared
        UpdaterCoordinator.shared.start()

        // Stamp the install date once; About → Stats reads this for "User since".
        if UserDefaults.standard.object(forKey: PrefsKey.firstLaunchDate) == nil {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: PrefsKey.firstLaunchDate)
        }

        menuBar.install(
            engine: engine,
            permissions: permissions,
            openSettings: { [weak self] in self?.openSettings() }
        )

        if let until = UserDefaults.standard.object(forKey: PrefsKey.pausedUntil) as? TimeInterval {
            let date = Date(timeIntervalSince1970: until)
            if date > Date() { engine.pausedUntil = date }
        }

        // Global pause/resume shortcuts. Uses Carbon hotkeys via KeyboardShortcuts,
        // which is independent of our CGEventTap — so the hotkeys still work
        // when Mojito is paused or when Input Monitoring is revoked. Pressing
        // EITHER shortcut while paused resumes (regardless of how the pause
        // was started); pressing while running pauses for the bound duration.
        KeyboardShortcuts.onKeyDown(for: .pauseHour) { [weak self] in
            self?.toggleOrPause(until: Date().addingTimeInterval(3600))
        }
        KeyboardShortcuts.onKeyDown(for: .pauseUntilTomorrow) { [weak self] in
            self?.toggleOrPause(until: Self.tomorrowMorning())
        }

        // Force onboarding any time required permissions aren't granted — that way revoked
        // permissions or a fresh macOS account always get the guided fix flow, not a
        // silently-broken menu bar app.
        let needsOnboarding = !UserDefaults.standard.bool(forKey: PrefsKey.onboardingComplete)
            || !permissions.allGranted
        if needsOnboarding {
            openOnboarding()
        } else {
            engine.start()
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
            }
            .store(in: &observers)

        NotificationCenter.default.publisher(for: .mojitoShouldOpenSettings)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.openSettings() }
            .store(in: &observers)
    }

    func applicationWillTerminate(_ notification: Notification) {
        os_log("applicationWillTerminate", log: log, type: .info)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Called when the user re-launches the app from Finder / Dock / Spotlight
    /// while it's already running. Without this, an `LSUIElement` app silently
    /// no-ops — frustrating because clicking the .app feels broken. Open
    /// Settings (or onboarding, if it hasn't completed) so the click does
    /// something visible.
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

    /// Assigns the bundle's on-disk icon to the running app. Bypasses
    /// LaunchServices' icon cache, which can lag behind when the bundle's
    /// icon changes (most visibly the dev build's `AppIconDev` swap).
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

    /// `LSUIElement: true` apps don't get a default app menu, which means standard
    /// keyboard shortcuts like ⌘Q don't fire when an app window (onboarding, settings)
    /// has focus. We install a minimal menu so those windows respond to the usual
    /// shortcuts; the menu bar itself stays hidden because of LSUIElement.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        // App menu (the standard "Mojito" menu with Quit, Hide, etc.)
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

        // Edit menu — without ⌘C/⌘V/⌘A wired through, text fields in Settings and
        // onboarding don't get standard copy/paste/select-all.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut",     action: #selector(NSText.cut(_:)),       keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",    action: #selector(NSText.copy(_:)),      keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",   action: #selector(NSText.paste(_:)),     keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Window menu — so ⌘W closes the current window cleanly.
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
