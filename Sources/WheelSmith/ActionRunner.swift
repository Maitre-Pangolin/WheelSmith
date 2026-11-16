import AppKit
import ApplicationServices
import RingCore

/// Where the wheel was opened, so actions can favour that display.
struct ActionContext {
    var layout: DisplayLayout?
    /// Index into `layout` of the display under the wheel (and so under the cursor).
    var displayIndex: Int?
    /// The slice app's windows, as listed when the wheel opened. nil when they weren't loaded yet.
    var windows: [WindowInfo]?

    static let none = ActionContext()
}

enum ActionRunner {
    static func run(_ action: Action, context: ActionContext = .none) {
        switch action {
        case .app(let bundleId):
            focus(bundleId, context: context)
        case .url(let text, let bundleId):
            openURL(text, with: bundleId)
        case .keys(let combo, let bundleId):
            sendShortcut(combo, to: bundleId, context: context)
        case .menu(let path, let bundleId):
            pressMenu(path, in: bundleId, context: context)
        case .shell(let command):
            runShell(command)
        case .prompt:
            break // The wheel handles it: it stays open with a text field (see WheelController.beginPrompt).
        case .none:
            break
        }
    }

    // MARK: Apps

    /// Brings the app forward with its main window moved onto the wheel's display, so it never
    /// comes up on the display it was last on. Without Accessibility, or when the app isn't running
    /// yet: like a Dock click.
    static func focus(_ bundleId: String, context: ActionContext = .none, completion: (() -> Void)? = nil) {
        let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
        guard isRunning, let layout = context.layout, let display = context.displayIndex else {
            activate(bundleId, completion: completion)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            // Prefer the windows listed when the wheel opened: listing again now can time out on slow
            // apps (Electron ones such as Slack), which would fall back to a Dock click that moves nothing.
            let listed = context.windows.flatMap { $0.isEmpty ? nil : $0 }
                ?? Windows.list(bundleId: bundleId, layout: layout, timeout: 1)
            let windows = listed.filter { !$0.isMinimized }
            let target = windows.first(where: \.isMain) ?? windows.first
            var activated = false
            if let target {
                Windows.move(target, toDisplay: display, layout: layout)
                activated = Windows.raise(target)
            }
            DispatchQueue.main.async {
                // A window on another Space is already in front (and its Space shown); a Dock-style
                // activation now could switch back to the app's last used Space.
                if activated { completion?() } else { activate(bundleId, raising: target, completion: completion) }
            }
        }
    }

    /// Focus one specific window (picked from the wheel's window ring), moved onto the wheel's display.
    static func focus(window: WindowInfo, of bundleId: String, context: ActionContext) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let display = context.displayIndex, let layout = context.layout {
                Windows.move(window, toDisplay: display, layout: layout)
            }
            if !Windows.raise(window) {
                DispatchQueue.main.async { activate(bundleId, raising: window) }
            }
        }
    }

    /// Like clicking the Dock icon: launches if needed, brings it forward, reopens a window if it has none.
    private static func activate(_ bundleId: String, raising window: WindowInfo? = nil, completion: (() -> Void)? = nil) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            NSSound.beep()
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { NSLog("WheelSmith: could not open \(bundleId): \(error)") }
            // Activation can reorder windows; make sure the chosen one ends up in front.
            if let window { DispatchQueue.global(qos: .userInitiated).async { Windows.raise(window) } }
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    // MARK: URLs & files

    static func openURL(_ text: String, with bundleId: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let url: URL?
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        } else {
            url = URL(string: trimmed)
        }
        guard let url else { NSSound.beep(); return }
        if let bundleId, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Shell

    /// Started by launchd, the app gets a bare PATH, and `zsh -lc` doesn't read ~/.zshrc, where tools in
    /// ~/.local/bin or Homebrew are usually added (an interactive shell would, but can take seconds to start).
    /// So the usual places for your own tools come first.
    static let shellEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let current = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        let extra = ["\(home)/.local/bin", "\(home)/bin", "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"]
        env["PATH"] = (extra.filter { !current.contains($0) } + current).joined(separator: ":")
        return env
    }()

    static func runShell(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.environment = shellEnvironment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { NSLog("WheelSmith: shell failed: \(error)"); NSSound.beep() }
    }

    // MARK: Keyboard shortcuts

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security → Accessibility.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func sendShortcut(_ text: String, to bundleId: String?, context: ActionContext = .none) {
        guard let combo = KeyCombo(text), let code = KeyboardLayout.keyCode(for: combo.key) else {
            NSSound.beep()
            return
        }
        guard hasAccessibility else {
            requestAccessibility()
            return
        }
        whenReady(bundleId, context: context) { post(code: code, flags: CGEventFlags(combo.modifiers.map(\.cgFlag))) }
    }

    // MARK: Menu items

    /// Brings the app forward, then clicks the menu item at `path` (e.g. ["Shell", "New Tab"]).
    static func pressMenu(_ path: [String], in bundleId: String?, context: ActionContext = .none) {
        guard !path.isEmpty else { NSSound.beep(); return }
        guard hasAccessibility else {
            requestAccessibility()
            return
        }
        whenReady(bundleId, context: context) {
            let app = bundleId.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
                ?? NSWorkspace.shared.frontmostApplication
            guard let pid = app?.processIdentifier else { NSSound.beep(); return }
            // AX calls block until the app answers (or a dialog it opens returns): keep them off the main thread.
            DispatchQueue.global(qos: .userInitiated).async {
                if !MenuBar.press(path: path, pid: pid) {
                    DispatchQueue.main.async {
                        NSLog("WheelSmith: menu item not found: \(MenuPath.display(path))")
                        NSSound.beep()
                    }
                }
            }
        }
    }

    /// Runs `body` once `bundleId` (if any) is frontmost and the hotkey's modifiers are up.
    private static func whenReady(_ bundleId: String?, context: ActionContext, then body: @escaping () -> Void) {
        if let bundleId, NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundleId {
            let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
            focus(bundleId, context: context)
            waitUntil(timeout: wasRunning ? 1.5 : 8, {
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId && modifiersReleased
            }) {
                // Give a freshly launched app a moment to put up its first window.
                DispatchQueue.main.asyncAfter(deadline: .now() + (wasRunning ? 0.05 : 0.6), execute: body)
            }
        } else {
            waitUntil(timeout: 1, { modifiersReleased }, then: body)
        }
    }

    /// The physical ⌥ from the hotkey must be up, or it would merge into the shortcut we send.
    private static var modifiersReleased: Bool {
        NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    }

    private static func post(code: UInt16, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func waitUntil(timeout: TimeInterval, _ condition: @escaping () -> Bool, then: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func check() {
            if condition() { then(); return }
            guard Date() < deadline else { NSLog("WheelSmith: timed out waiting for the target app"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: check)
        }
        check()
    }
}
