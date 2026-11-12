import AppKit
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: ConfigStore
    private let launchAtLogin: LaunchAtLogin
    private var window: NSWindow?

    init(store: ConfigStore, launchAtLogin: LaunchAtLogin) {
        self.store = store
        self.launchAtLogin = launchAtLogin
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "WheelSmith"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 900, height: 580)
            window.contentView = NSHostingView(rootView: SettingsView(store: store, launchAtLogin: launchAtLogin))
            window.center()
            window.delegate = self
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Drop the SwiftUI tree so the app idles at minimal memory.
        window?.contentView = nil
        window = nil
    }
}
