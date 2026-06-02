import AppKit
import Combine
import KeyboardShortcuts

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
    private weak var browseItem: NSMenuItem?
    private var updateBadge: NSView?

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
            .sink { [weak self] _, _, _ in
                self?.applyStatusIcon()
                self?.refreshMenu()
            }
            .store(in: &observers)

        UpdaterCoordinator.shared.$hasUpdateError
            .combineLatest(UpdaterCoordinator.shared.$hasUpdateAvailable)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.applyStatusIcon()
                self?.refreshUpdatesItem()
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
        item.menu = buildMenu()
        statusItem = item
        applyStatusIcon()
        refreshMenu()
        refreshUpdatesItem()
    }

    // MARK: - Icon

    /// Reads the live engine/permission/updater state and repaints the icon.
    /// Called from both Combine sinks so any of the three inputs refreshes it.
    private func applyStatusIcon() {
        guard let button = statusItem?.button else { return }
        let ax = permissions?.accessibility ?? false
        let im = permissions?.inputMonitoring ?? false
        // Only warn post-onboarding. During onboarding the missing permissions
        // are expected and the flow already shows them.
        let onboardingComplete = UserDefaults.standard.bool(forKey: PrefsKey.onboardingComplete)
        let hasIssue = onboardingComplete && !(ax && im)
        let active = (engine?.isActive ?? true) && ax && im
        applyIcon(to: button,
                  active: active,
                  hasIssue: hasIssue,
                  updateAvailable: UpdaterCoordinator.shared.hasUpdateAvailable)
    }

    /// Text fallback because a `variableLength` status item with no image
    /// renders at 0pt — completely invisible.
    private func applyIcon(to button: NSStatusBarButton, active: Bool, hasIssue: Bool, updateAvailable: Bool) {
        if hasIssue, let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: String(localized: "\(AppInfo.displayName) needs permission")) {
            image.isTemplate = false  // keep yellow tint
            button.image = image
            button.title = ""
            setUpdateBadge(false, on: button)
            return
        }

        if let image = NSImage(named: "MenuBarIcon") {
            // ~15–16pt matches Apple's menu-bar icons. SVG is 128×119.
            image.size = NSSize(width: 16, height: 15)
            image.isTemplate = true  // system tints it correctly for the menu bar
            // Softens template tint when paused.
            button.appearsDisabled = !active
            button.image = image
            button.title = ""
            setUpdateBadge(updateAvailable, on: button)
            return
        }

        button.image = nil
        button.title = hasIssue ? "⚠️" : "🍹"
        setUpdateBadge(false, on: button)
    }

    /// A small yellow "update available" dot pinned to the top-right of the
    /// status button. A subview rather than a composited image, so the glyph
    /// stays a template the system tints correctly for the menu bar's light/
    /// dark state (compositing forces a non-template image that mis-tints).
    private func setUpdateBadge(_ visible: Bool, on button: NSStatusBarButton) {
        guard visible else { updateBadge?.isHidden = true; return }
        let d: CGFloat = 6
        // Distance from the top / right edges — nudged in so the dot sits on
        // the glyph's upper-right rather than floating in the corner.
        let rightInset: CGFloat = 7
        let topInset: CGFloat = 3
        // Status buttons draw flipped (top-left origin), so "top" is y≈0.
        // Branch on isFlipped so the dot lands consistently either way.
        let x = button.bounds.maxX - d - rightInset
        let y = button.isFlipped ? topInset : (button.bounds.maxY - d - topInset)
        let frame = NSRect(x: x, y: y, width: d, height: d)
        if let badge = updateBadge {
            badge.frame = frame
            badge.isHidden = false
        } else {
            let badge = NSView(frame: frame)
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.systemYellow.cgColor
            badge.layer?.cornerRadius = d / 2
            button.addSubview(badge)
            updateBadge = badge
        }
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
        let browse = NSMenuItem(title: String(localized: "Browse Emoji…"), action: #selector(MenuActions.openBrowser), keyEquivalent: "").configured(target: MenuActions.shared)
        // Displays (and keeps in sync) the user's assigned browser hotkey.
        browse.setShortcut(for: .showEmojiBrowser)
        menu.addItem(browse)
        browseItem = browse
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
        refreshUpdatesItem()
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
        // Browser insertion goes dark when paused / permissions are missing
        // (showBrowser guards on isActive), so the item shouldn't look live.
        browseItem?.isEnabled = engine?.isActive ?? false
    }

    private func refreshUpdatesItem() {
        guard let item = checkForUpdatesItem else { return }
        if UpdaterCoordinator.shared.hasUpdateAvailable {
            // Available beats the error state: clicking re-shows Sparkle's
            // dialog so the user can install (or defer again).
            item.title = String(localized: "Update available…")
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemYellow])
            item.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: String(localized: "Update available"))?
                .withSymbolConfiguration(config)
            item.image?.isTemplate = false
            item.toolTip = String(localized: "A new version of \(AppInfo.displayName) is ready to install.")
        } else if UpdaterCoordinator.shared.hasUpdateError {
            // Quieter than a modal but still discoverable.
            item.title = String(localized: "Check for Updates…")
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: String(localized: "Update check failed"))
            item.image?.isTemplate = false
            item.toolTip = String(localized: "\(AppInfo.displayName) couldn't reach the update server.")
        } else {
            item.title = String(localized: "Check for Updates…")
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

    fileprivate func performOpenBrowser() {
        NotificationCenter.default.post(name: .mojitoShouldOpenBrowser, object: nil)
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
    @objc func openBrowser() { controller?.performOpenBrowser() }
    @objc func showOnboarding() { controller?.performShowOnboarding() }
    @objc func checkForUpdates() { controller?.performCheckForUpdates() }
}

private extension NSMenuItem {
    func configured(target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}
