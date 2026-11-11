import AppKit
import SwiftUI
import RingCore

/// `TheOneRing --snapshot <dir>`: renders the wheel in a few states and the Settings window to PNGs.
/// Uses an opaque backdrop because behind-window blur can't be captured off-screen.
@MainActor
enum Snapshot {
    static func run(outputDirectory: String) {
        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let config = DefaultConfig.config
        IconCache.shared.preload(config.items)

        let states: [(String, String, WheelHit, Int?)] = [
            ("wheel-midnight-center", "midnight", .center, nil),
            ("wheel-midnight-slice", "midnight", .item(7), 7),
            ("wheel-midnight-sub", "midnight", .child(2, 2), 2),
            ("wheel-daylight-sub", "daylight", .child(0, 1), 0),
            ("wheel-glass-slice", "glass", .item(4), 4),
        ]
        for (name, themeId, hit, parent) in states {
            let theme = Theme.named(themeId)
            let view = ZStack {
                LinearGradient(colors: theme.isDark
                               ? [Color(red: 0.13, green: 0.09, blue: 0.27), Color(red: 0.02, green: 0.04, blue: 0.11)]
                               : [Color(red: 0.95, green: 0.91, blue: 0.99), Color(red: 0.84, green: 0.91, blue: 0.99)],
                               startPoint: .top, endPoint: .bottom)
                WheelCanvas(items: config.items, theme: theme, hit: hit, openParent: parent, opaqueBackdrop: true)
            }
            let size = WheelMetrics.standard.canvasSize
            render(view, size: CGSize(width: size, height: size), to: dir.appendingPathComponent(name + ".png"))
        }

        let tmpConfig = FileManager.default.temporaryDirectory.appendingPathComponent("theonering-snapshot/config.json")
        try? FileManager.default.removeItem(at: tmpConfig)
        let store = ConfigStore(url: tmpConfig)
        render(SettingsView(store: store, launchAtLogin: LaunchAtLogin()),
               size: CGSize(width: 980, height: 640), to: dir.appendingPathComponent("settings.png"))
        render(SettingsView(store: store, launchAtLogin: LaunchAtLogin(), tab: .general),
               size: CGSize(width: 980, height: 640), to: dir.appendingPathComponent("settings-general.png"))
        // Sample data: the live scan needs Accessibility, which an offscreen render doesn't have.
        let sample: [MenuCommand] = [
            .init(path: ["Shell", "New Window"], shortcut: "⌘N", enabled: true),
            .init(path: ["Shell", "New Tab"], shortcut: "⌘T", enabled: true),
            .init(path: ["Shell", "Split Vertically with Current Profile"], shortcut: "⌘D", enabled: true),
            .init(path: ["Shell", "Split Horizontally with Current Profile"], shortcut: "⇧⌘D", enabled: true),
            .init(path: ["Shell", "Close"], shortcut: "⌘W", enabled: true),
            .init(path: ["Edit", "Find", "Find…"], shortcut: "⌘F", enabled: true),
            .init(path: ["Edit", "Clear Buffer"], shortcut: "⌘K", enabled: true),
            .init(path: ["View", "Enter Full Screen"], shortcut: "⌃⌘F", enabled: true),
            .init(path: ["Window", "Minimize"], shortcut: "⌘M", enabled: false),
        ]
        // Window ring: iTerm (slice 7) with three windows across two displays, hovering the second.
        let dummy = AXUIElementCreateApplication(0)
        func window(_ title: String, display: Int, minimized: Bool = false) -> WindowInfo {
            WindowInfo(element: dummy, title: title, frame: .zero, isMinimized: minimized, isFullScreen: false,
                       displayIndex: display)
        }
        let itermWindows = [window("~/perso/TheOneRing", display: 0), window("ssh prod-api", display: 1),
                            window("htop", display: 1, minimized: true)]
        let midnight = Theme.named("midnight")
        let windowRing = ZStack {
            LinearGradient(colors: [Color(red: 0.13, green: 0.09, blue: 0.27), Color(red: 0.02, green: 0.04, blue: 0.11)],
                           startPoint: .top, endPoint: .bottom)
            WheelCanvas(items: config.items, theme: midnight, hit: .child(7, 1), openParent: 7, opaqueBackdrop: true,
                        windows: [7: itermWindows], hereDisplay: 0, displayCount: 2)
        }
        let side = WheelMetrics.standard.canvasSize
        render(windowRing, size: CGSize(width: side, height: side), to: dir.appendingPathComponent("wheel-windows.png"))

        render(MenuBrowserSheet(bundleId: DefaultConfig.BundleID.iterm, mode: .addMany(limit: 3), preset: sample) { _ in },
               size: CGSize(width: 580, height: 620), to: dir.appendingPathComponent("menu-browser.png"))
        print("Snapshots written to \(dir.path)")
    }

    private static func render<V: View>(_ view: V, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4)) // let SwiftUI settle animations
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
