import AppKit
import Combine

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private weak var engine: Engine?
    private weak var permissions: PermissionsCoordinator?
    private var openSettings: (() -> Void)?
    private var observers = Set<AnyCancellable>()
    private var showPrefCancellable: AnyCancellable?
    private weak var checkForUpdatesItem: NSMenuItem?
    private weak var resumeItem: NSMenuItem?
    private weak var pauseHourItem: NSMenuItem?
    private weak var pauseTomorrowItem: NSMenuItem?

    func install(
        engine: Engine,
        permissions: PermissionsCoordinator,
        openSettings: @escaping () -> Void
    ) {
        // Re-entrant guard: pref-flip toggles call back into install() to
        // recreate the status item without re-registering Combine observers.
        guard self.engine == nil else {
            createStatusItemIfNeeded()
            return
        }

        self.engine = engine
        self.permissions = permissions
        self.openSettings = openSettings

        engine.$isActive
            .combineLatest(permissions.$accessibility, permissions.$inputMonitoring)
            .receive(on: RunLoop.main)
            .sink { [weak self] isActive, ax, im in
                // Only warn post-onboarding. During onboarding the missing
                // permissions are expected and the flow already shows them.
                let onboardingComplete = UserDefaults.standard.bool(forKey: PrefsKey.onboardingComplete)
                let hasIssue = onboardingComplete && !(ax && im)
                self?.refreshIcon(active: isActive && ax && im, hasIssue: hasIssue)
                self?.refreshMenu()
            }
            .store(in: &observers)

        UpdaterCoordinator.shared.$hasUpdateError
            .receive(on: RunLoop.main)
            .sink { [weak self] hasError in
                self?.refreshUpdatesItem(hasError: hasError)
            }
            .store(in: &observers)

        showPrefCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if Self.shouldShowMenuBarIcon {
                    self.createStatusItemIfNeeded()
                } else {
                    self.remove()
                }
            }

        if Self.shouldShowMenuBarIcon {
            createStatusItemIfNeeded()
        }
    }

    func remove() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    private static var shouldShowMenuBarIcon: Bool {
        (UserDefaults.standard.object(forKey: PrefsKey.showMenuBarIcon) as? Bool) ?? true
    }

    private func createStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            applyIcon(to: button, active: engine?.isActive ?? true, hasIssue: false)
        }
        item.menu = buildMenu()
        statusItem = item
        refreshMenu()
        refreshUpdatesItem(hasError: UpdaterCoordinator.shared.hasUpdateError)
    }

    // MARK: - Icon

    private func refreshIcon(active: Bool, hasIssue: Bool) {
        guard let button = statusItem?.button else { return }
        applyIcon(to: button, active: active, hasIssue: hasIssue)
    }

    /// Text fallback because a `variableLength` status item with no image
    /// renders at 0pt — completely invisible.
    private func applyIcon(to button: NSStatusBarButton, active: Bool, hasIssue: Bool) {
        if hasIssue, let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: String(localized: "\(AppInfo.displayName) needs permission")) {
            image.isTemplate = false  // keep yellow tint
            button.image = image
            button.title = ""
            return
        }

        if let image = NSImage(named: "MenuBarIcon") {
            // ~15–16pt matches Apple's menu-bar icons. SVG is 128×119.
            image.size = NSSize(width: 16, height: 15)
            image.isTemplate = true
            // Softens template tint when paused.
            button.appearsDisabled = !active
            button.image = image
            button.title = ""
            return
        }

        button.image = nil
        button.title = hasIssue ? "⚠️" : "🍹"
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = MenuDelegateBridge.shared
        menu.autoenablesItems = false

        menu.addItem(makeStatusItem())
        menu.addItem(.separator())

        let pauseHour = NSMenuItem(title: String(localized: "Pause for 1 hour"), action: #selector(MenuActions.pauseHour), keyEquivalent: "").configured(target: MenuActions.shared)
        menu.addItem(pauseHour)
        pauseHourItem = pauseHour

        let pauseTomorrow = NSMenuItem(title: String(localized: "Pause until tomorrow"), action: #selector(MenuActions.pauseUntilTomorrow), keyEquivalent: "").configured(target: MenuActions.shared)
        menu.addItem(pauseTomorrow)
        pauseTomorrowItem = pauseTomorrow

        let resume = NSMenuItem(title: String(localized: "Resume"), action: #selector(MenuActions.resume), keyEquivalent: "").configured(target: MenuActions.shared)
        menu.addItem(resume)
        resumeItem = resume

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Settings…"), action: #selector(MenuActions.openSettings), keyEquivalent: ",").configured(target: MenuActions.shared))
        // Option-held alternate — backdoor for re-running guided setup
        // without resetting onboarding state. Discoverability intentionally low.
        let showOnboarding = NSMenuItem(title: String(localized: "Show Onboarding"), action: #selector(MenuActions.showOnboarding), keyEquivalent: ",").configured(target: MenuActions.shared)
        showOnboarding.keyEquivalentModifierMask = [.command, .option]
        showOnboarding.isAlternate = true
        menu.addItem(showOnboarding)
        let updatesItem = NSMenuItem(title: String(localized: "Check for Updates…"), action: #selector(MenuActions.checkForUpdates), keyEquivalent: "").configured(target: MenuActions.shared)
        menu.addItem(updatesItem)
        checkForUpdatesItem = updatesItem
        refreshUpdatesItem(hasError: UpdaterCoordinator.shared.hasUpdateError)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit \(AppInfo.displayName)"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        MenuActions.shared.bind(self)
        return menu
    }

    fileprivate func refreshMenu() {
        guard let menu = statusItem?.menu, let statusRow = menu.item(at: 0) else { return }
        statusRow.attributedTitle = statusTitle()

        let isPaused = (engine?.pausedUntil.map { $0 > Date() } ?? false)
        pauseHourItem?.isHidden = isPaused
        pauseTomorrowItem?.isHidden = isPaused
        resumeItem?.isHidden = !isPaused
    }

    private func refreshUpdatesItem(hasError: Bool) {
        guard let item = checkForUpdatesItem else { return }
        item.title = String(localized: "Check for Updates…")
        if hasError {
            // Quieter than a modal but still discoverable.
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: String(localized: "Update check failed"))
            item.image?.isTemplate = false
            item.toolTip = String(localized: "\(AppInfo.displayName) couldn't reach the update server.")
        } else {
            item.image = nil
            item.toolTip = nil
        }
    }

    private func makeStatusItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "\(AppInfo.displayName) is on"), action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = statusTitle()
        return item
    }

    private func statusTitle() -> NSAttributedString {
        let active = engine?.isActive ?? false
        let permissionsOK = (permissions?.allGranted) ?? false
        let name = AppInfo.displayName
        let title: String = {
            if !permissionsOK { return String(localized: "\(name) needs permission") }
            if let until = engine?.pausedUntil, until > Date() { return String(localized: "\(name) is paused") }
            return active
                ? String(localized: "\(name) is running 🏃‍♂️")
                : String(localized: "\(name) is off")
        }()
        return NSAttributedString(string: title, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
    }

    fileprivate func performPauseHour() {
        engine?.pause(until: Date().addingTimeInterval(3600))
    }

    fileprivate func performPauseUntilTomorrow() {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.day = (components.day ?? 0) + 1
        components.hour = 7
        let date = Calendar.current.date(from: components) ?? Date().addingTimeInterval(8 * 3600)
        engine?.pause(until: date)
    }

    fileprivate func performResume() {
        engine?.resume()
    }

    fileprivate func performOpenSettings() {
        openSettings?()
    }

    fileprivate func performShowOnboarding() {
        NotificationCenter.default.post(name: .mojitoShouldShowOnboarding, object: nil)
    }

    fileprivate func performCheckForUpdates() {
        UpdaterCoordinator.shared.checkForUpdates()
    }
}

@MainActor
private final class MenuDelegateBridge: NSObject, NSMenuDelegate {
    static let shared = MenuDelegateBridge()
}

@MainActor
private final class MenuActions: NSObject {
    static let shared = MenuActions()
    private weak var controller: MenuBarController?

    func bind(_ controller: MenuBarController) {
        self.controller = controller
    }

    @objc func pauseHour() { controller?.performPauseHour() }
    @objc func pauseUntilTomorrow() { controller?.performPauseUntilTomorrow() }
    @objc func resume() { controller?.performResume() }
    @objc func openSettings() { controller?.performOpenSettings() }
    @objc func showOnboarding() { controller?.performShowOnboarding() }
    @objc func checkForUpdates() { controller?.performCheckForUpdates() }
}

private extension NSMenuItem {
    func configured(target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}
