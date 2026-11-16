import AppKit
import Combine
import RingCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var store: ConfigStore!
    private let launchAtLogin = LaunchAtLogin()
    private var wheel: WheelController!
    private var settings: SettingsWindowController!
    private var statusItem: NSStatusItem!
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one WheelSmith at a time (e.g. LaunchAgent + manual open).
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }

        store = ConfigStore()
        wheel = WheelController()
        settings = SettingsWindowController(store: store, launchAtLogin: launchAtLogin)
        wheel.onOpenSettings = { [weak self] in self?.settings.show() }

        let hotkeys = HotkeyManager.shared
        hotkeys.onPress = { [weak self] in self?.wheel.open() }
        hotkeys.onRelease = { [weak self] in self?.wheel.release() }
        hotkeys.onEscape = { [weak self] in self?.wheel.cancel() }
        hotkeys.onArrow = { [weak self] arrow in self?.wheel.arrow(arrow) }
        wheel.onThemeChange = { [weak self] id in self?.store.config.theme = id }

        store.$config
            .removeDuplicates()
            .sink { [weak self] config in self?.apply(config) }
            .store(in: &cancellables)

        setupStatusItem()
        launchAtLogin.enableOnFirstRun()
    }

    private func apply(_ config: RingConfig) {
        // A theme that no longer exists (Liquid Glass) moves to its replacement, and is saved.
        let theme = ThemeCatalog.resolve(config.theme)
        if theme != config.theme {
            store.config.theme = theme
            return
        }
        wheel.apply(config: config)
        if KeyCombo(config.hotkey) != HotkeyManager.shared.combo {
            HotkeyManager.shared.setHotkey(KeyCombo(config.hotkey) ?? KeyCombo("option+space"))
        }
        updateStatusIcon()
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let failed = HotkeyManager.shared.registrationError != nil || store.lastError != nil
        let image = failed
            ? NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "WheelSmith")
            : Self.logoImage
        image?.isTemplate = true
        button.image = image
    }

    /// The ring-and-raised-segment mark, drawn as a vector so it stays crisp at any scale.
    private static let logoImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(LogoMark().path(in: rect))
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            return true
        }
        image.accessibilityDescription = "WheelSmith"
        return image
    }()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let hotkey = KeyCombo(store.config.hotkey)?.display ?? store.config.hotkey
        let header = NSMenuItem(title: "WheelSmith — hold \(hotkey)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for problem in [HotkeyManager.shared.registrationError, store.lastError].compactMap({ $0 }) {
            let item = NSMenuItem(title: "⚠︎ \(problem)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Edit config.json", #selector(editConfig)))
        menu.addItem(.separator())
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = launchAtLogin.isEnabled ? .on : .off
        login.isEnabled = launchAtLogin.isAvailable
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Quit WheelSmith", #selector(quit), key: "q"))
        updateStatusIcon()
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSettings() { settings.show() }
    @objc private func editConfig() { NSWorkspace.shared.open(store.url) }
    @objc private func toggleLaunchAtLogin() { launchAtLogin.isEnabled.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// Opening the app again (Spotlight, Finder, `open -a WheelSmith`) shows Settings. This is the way
    /// in when the menu-bar icon is hidden, e.g. pushed behind the notch on a full menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }
}
