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
            self?.engine.showBrowser()
        }

        // Force onboarding any time permissions aren't granted — revoked
        // perms / fresh accounts get the guided fix, not a silent break.
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
                // Drop the onboarding fast-poll back to the baseline cadence.
                self?.permissions.startMonitoring()
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        os_log("applicationWillTerminate", log: log, type: .info)
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
