import AppKit
import Combine

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private weak var engine: Engine?
    private weak var permissions: PermissionsCoordinator?
    private var openSettings: (() -> Void)?
    private var observers = Set<AnyCancellable>()
    private weak var checkForUpdatesItem: NSMenuItem?
    private weak var resumeItem: NSMenuItem?
    private weak var pauseHourItem: NSMenuItem?
    private weak var pauseTomorrowItem: NSMenuItem?

    func install(
        engine: Engine,
        permissions: PermissionsCoordinator,
        openSettings: @escaping () -> Void
    ) {
        self.engine = engine
        self.permissions = permissions
        self.openSettings = openSettings

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            applyIcon(to: button, active: true, hasIssue: false)
        }
        item.menu = buildMenu()
        statusItem = item

        engine.$isActive
            .combineLatest(permissions.$accessibility, permissions.$inputMonitoring)
            .receive(on: RunLoop.main)
            .sink { [weak self] isActive, ax, im in
                // Only treat missing permissions as a "warning" state AFTER the user
                // has finished onboarding. Before onboarding completes, the missing
                // permissions are expected — the onboarding flow is already on screen
                // asking the user to grant them, so replacing the menu bar icon with
                // a yellow triangle on top of that would be noisy and redundant.
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
    }

    // MARK: - Icon

    private func refreshIcon(active: Bool, hasIssue: Bool) {
        guard let button = statusItem?.button else { return }
        applyIcon(to: button, active: active, hasIssue: hasIssue)
    }

    /// Apply the menu-bar icon defensively. The active/idle states use a custom vector
    /// asset (`MenuBarIcon` from the asset catalog) rendered as a template image so macOS
    /// tints it for light/dark menu bars automatically. The error state uses the system
    /// warning-triangle symbol (kept colored so it stands out). If any asset lookup fails
    /// we fall back to a text glyph, since a `variableLength` status item with a `nil`
    /// image renders at 0pt — i.e. completely invisible.
    private func applyIcon(to button: NSStatusBarButton, active: Bool, hasIssue: Bool) {
        if hasIssue, let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "\(AppInfo.displayName) needs permission") {
            image.isTemplate = false  // keep the yellow tint
            button.image = image
            button.title = ""
            return
        }

        if let image = NSImage(named: "MenuBarIcon") {
            // Standard menu-bar icons are ~15–16pt to match Apple's own (Wi-Fi,
            // Battery, etc.). Preserves the SVG's aspect ratio (128×119 → 16×14.9).
            image.size = NSSize(width: 16, height: 15)
            image.isTemplate = true
            // Dim the icon a touch when paused — same logic as the old wineglass/wineglass.fill
            // pairing. `appearsDisabled` softens the template tint.
            button.appearsDisabled = !active
            button.image = image
            button.title = ""
            return
        }

        // Asset load failed — fall back to text so the item is at least clickable.
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

        let pauseHour = NSMenuItem(title: "Pause for 1 hour", action: #selector(MenuActions.pauseHour), keyEquivalent: "").configured(target: MenuActions.shared)
        menu.addItem(pauseHour)
        pauseHourItem = pauseHour

        let pauseTomorrow = NSMenuItem(title: "Pause until tomorrow", action: #selector(MenuActions.pauseUntilTomorrow), keyEquivalent: "").configured(target: MenuActions.shared)
        menu.addItem(pauseTomorrow)
        pauseTomorrowItem = pauseTomorrow

        let resume = NSMenuItem(title: "Resume", action: #selector(MenuActions.resume), keyEquivalent: "").configured(target: MenuActions.shared)
        menu.addItem(resume)
        resumeItem = resume

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(MenuActions.openSettings), keyEquivalent: ",").configured(target: MenuActions.shared))
        // Hidden alternate revealed when the user holds Option while the
        // menu is open — replaces "Settings…" in place. Discoverability is
        // intentionally low; this is a backdoor for re-running the guided
        // setup without resetting onboarding state.
        let showOnboarding = NSMenuItem(title: "Show Onboarding", action: #selector(MenuActions.showOnboarding), keyEquivalent: ",").configured(target: MenuActions.shared)
        showOnboarding.keyEquivalentModifierMask = [.command, .option]
        showOnboarding.isAlternate = true
        menu.addItem(showOnboarding)
        let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(MenuActions.checkForUpdates), keyEquivalent: "").configured(target: MenuActions.shared)
        menu.addItem(updatesItem)
        checkForUpdatesItem = updatesItem
        refreshUpdatesItem(hasError: UpdaterCoordinator.shared.hasUpdateError)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit \(AppInfo.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        MenuActions.shared.bind(self)
        return menu
    }

    fileprivate func refreshMenu() {
        guard let menu = statusItem?.menu, let statusRow = menu.item(at: 0) else { return }
        statusRow.attributedTitle = statusTitle()

        // Pause/Resume are mutually exclusive — only show the one that's applicable.
        let isPaused = (engine?.pausedUntil.map { $0 > Date() } ?? false)
        pauseHourItem?.isHidden = isPaused
        pauseTomorrowItem?.isHidden = isPaused
        resumeItem?.isHidden = !isPaused
    }

    private func refreshUpdatesItem(hasError: Bool) {
        guard let item = checkForUpdatesItem else { return }
        item.title = "Check for Updates…"
        if hasError {
            // Trailing yellow warning triangle — quieter than a modal, still discoverable.
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Update check failed")
            item.image?.isTemplate = false
            item.toolTip = "\(AppInfo.displayName) couldn't reach the update server."
        } else {
            item.image = nil
            item.toolTip = nil
        }
    }

    private func makeStatusItem() -> NSMenuItem {
        let item = NSMenuItem(title: "\(AppInfo.displayName) is on", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = statusTitle()
        return item
    }

    private func statusTitle() -> NSAttributedString {
        let active = engine?.isActive ?? false
        let permissionsOK = (permissions?.allGranted) ?? false
        let title: String = {
            let name = AppInfo.displayName
            if !permissionsOK { return "\(name) needs permission" }
            if let until = engine?.pausedUntil, until > Date() { return "\(name) is paused" }
            return active ? "\(name) is running 🏃‍♂️" : "\(name) is off"
        }()
        return NSAttributedString(string: title, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
    }

    // Internal access for MenuActions singleton callbacks
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
