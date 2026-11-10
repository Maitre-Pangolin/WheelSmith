import AppKit
import ApplicationServices
import RingCore

enum ActionRunner {
    static func run(_ action: Action) {
        switch action {
        case .app(let bundleId):
            focus(bundleId)
        case .url(let text, let bundleId):
            openURL(text, with: bundleId)
        case .keys(let combo, let bundleId):
            sendShortcut(combo, to: bundleId)
        case .shell(let command):
            runShell(command)
        case .none:
            break
        }
    }

    // MARK: Apps

    /// Like clicking the Dock icon: launches if needed, brings it forward, reopens a window if it has none.
    static func focus(_ bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            NSSound.beep()
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { NSLog("TheOneRing: could not open \(bundleId): \(error)") }
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

    static func runShell(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { NSLog("TheOneRing: shell failed: \(error)"); NSSound.beep() }
    }

    // MARK: Keyboard shortcuts

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security → Accessibility.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func sendShortcut(_ text: String, to bundleId: String?) {
        guard let combo = KeyCombo(text), let code = KeyboardLayout.keyCode(for: combo.key) else {
            NSSound.beep()
            return
        }
        guard hasAccessibility else {
            requestAccessibility()
            return
        }
        let send = { post(code: code, flags: CGEventFlags(combo.modifiers.map(\.cgFlag))) }
        if let bundleId, NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundleId {
            let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
            focus(bundleId)
            waitUntil(timeout: wasRunning ? 1.5 : 8, {
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId && modifiersReleased
            }) {
                // Give a freshly launched app a moment to put up its first window.
                DispatchQueue.main.asyncAfter(deadline: .now() + (wasRunning ? 0.05 : 0.6), execute: send)
            }
        } else {
            waitUntil(timeout: 1, { modifiersReleased }, then: send)
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
            guard Date() < deadline else { NSLog("TheOneRing: timed out waiting to send shortcut"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: check)
        }
        check()
    }
}
