import AppKit
import SwiftUI
import RingCore

/// `WheelSmith --snapshot <dir>`: renders the wheel in a few states and the Settings window to PNGs.
/// Uses an opaque backdrop because behind-window blur can't be captured off-screen.
@MainActor
enum Snapshot {
    static func run(outputDirectory: String) {
        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let config = DefaultConfig.config
        IconCache.shared.preload(config.items)

        let states: [(String, String, WheelHit, Int?, Bool)] = [
            ("wheel-midnight-center", "midnight", .center, nil, false),
            ("wheel-midnight-settings", "midnight", .center, nil, true),
            ("wheel-midnight-slice", "midnight", .item(7), 7, false),
            ("wheel-midnight-sub", "midnight", .child(3, 2), 3, false),
            ("wheel-daylight-sub", "daylight", .child(5, 0), 5, false),
            ("wheel-graphite-slice", "graphite", .item(4), 4, false),
            ("wheel-astrolabe-sub", "astrolabe", .child(3, 1), 3, false),
        ]
        for (name, themeId, hit, parent, armed) in states {
            let theme = Theme.named(themeId)
            let view = ZStack {
                LinearGradient(colors: theme.isDark
                               ? [Color(red: 0.13, green: 0.09, blue: 0.27), Color(red: 0.02, green: 0.04, blue: 0.11)]
                               : [Color(red: 0.95, green: 0.91, blue: 0.99), Color(red: 0.84, green: 0.91, blue: 0.99)],
                               startPoint: .top, endPoint: .bottom)
                // Unarmed: the ring partway through its first second.
                WheelCanvas(items: config.items, theme: theme, hit: hit, openParent: parent, opaqueBackdrop: true,
                            settingsArmed: armed, armProgress: armed ? 1 : 0.4)
            }
            let size = WheelMetrics.standard.canvasSize
            render(view, size: CGSize(width: size, height: size), to: dir.appendingPathComponent(name + ".png"))
        }

        let tmpConfig = FileManager.default.temporaryDirectory.appendingPathComponent("wheelsmith-snapshot/config.json")
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
        func window(_ title: String, display: Int, minimized: Bool = false, fullScreen: Bool = false) -> WindowInfo {
            WindowInfo(element: dummy, pid: 0, windowID: 0, title: title, frame: .zero, isMinimized: minimized,
                       isFullScreen: fullScreen, onCurrentSpace: !fullScreen, displayIndex: display)
        }
        let itermWindows = [window("~/perso/WheelSmith", display: 0), window("ssh prod-api", display: 1, fullScreen: true),
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

        // Prompt action: the wheel stays open on Ostraka › Quick todo with a text field over it.
        let ostraka = config.items.firstIndex { $0.label == "Ostraka" } ?? 0
        let geometry = WheelGeometry(childCounts: config.items.map(\.children.count))
        let offset = CGFloat(geometry.horizontalClearance(halfHeight: Stage.promptHalfHeight, openParent: ostraka))
            + Stage.promptGap + PromptCard.width / 2
        for (name, themeId, text, status) in [
            ("wheel-prompt-midnight", "midnight", "", PromptModel.Status.editing),
            ("wheel-prompt-daylight-done", "daylight", "Review the SCHED board #sched *high ^fri",
             .done("Sample output: Added todo “Review the SCHED board”")),
        ] {
            let theme = Theme.named(themeId)
            let prompt = PromptModel(title: "Quick todo", caption: "Ostraka",
                                     placeholder: "Review the board #tag *high ^fri", theme: theme)
            prompt.icon = .symbol("checklist")
            prompt.text = text
            prompt.status = status
            let view = ZStack {
                LinearGradient(colors: theme.isDark
                               ? [Color(red: 0.13, green: 0.09, blue: 0.27), Color(red: 0.02, green: 0.04, blue: 0.11)]
                               : [Color(red: 0.95, green: 0.91, blue: 0.99), Color(red: 0.84, green: 0.91, blue: 0.99)],
                               startPoint: .top, endPoint: .bottom)
                WheelCanvas(items: config.items, theme: theme, hit: .child(ostraka, 0), openParent: ostraka,
                            opaqueBackdrop: true, dimmed: true)
                PromptCard(model: prompt, opaqueBackdrop: true).offset(x: offset)
            }
            render(view, size: Stage.size(), to: dir.appendingPathComponent(name + ".png"))
        }
        // Right after pressing → to switch themes.
        let aurora = Theme.named("aurora")
        render(ZStack {
            DesignBackground(kind: "dusk")
            WheelCanvas(items: config.items, theme: aurora, hit: .center, openParent: nil, opaqueBackdrop: true,
                        armProgress: 0.4, themeToast: ThemeToast(name: aurora.name, detail: "Dark · 2 of 18"))
        }, size: CGSize(width: side, height: side), to: dir.appendingPathComponent("wheel-theme-switch.png"))

        // Every theme over the background it was designed on, with a sub-action hovered.
        let themeDir = dir.appendingPathComponent("themes")
        try? FileManager.default.createDirectory(at: themeDir, withIntermediateDirectories: true)
        let outlook = config.items.firstIndex { $0.label == "Outlook" } ?? 3
        for theme in Theme.catalog {
            render(themeCard(theme, items: config.items, hit: .child(outlook, 1), parent: outlook),
                   size: CGSize(width: side, height: side), to: themeDir.appendingPathComponent(theme.id + ".png"))
        }
        let columns = 8, cell: CGFloat = 300
        let sheet = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stride(from: 0, to: Theme.catalog.count, by: columns)), id: \.self) { start in
                HStack(spacing: 0) {
                    ForEach(Theme.catalog[start..<min(start + columns, Theme.catalog.count)], id: \.id) { theme in
                        ZStack(alignment: .bottomLeading) {
                            themeCard(theme, items: config.items, hit: .child(outlook, 1), parent: outlook)
                                .frame(width: side, height: side)
                                .scaleEffect(cell / side)
                                .frame(width: cell, height: cell)
                                .clipped()
                            Text(theme.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(.black.opacity(0.55)))
                                .padding(8)
                        }
                    }
                }
            }
        }
        let rows = (Theme.catalog.count + columns - 1) / columns
        render(sheet, size: CGSize(width: cell * CGFloat(columns), height: cell * CGFloat(rows)),
               to: dir.appendingPathComponent("themes.png"))
        let families = Set(Theme.catalog.flatMap { [$0.spec.hubFont?.family, $0.spec.labelFont?.family] }.compactMap { $0 })
        let missing = families.subtracting(ThemeFont.installed).sorted()
        print(missing.isEmpty ? "Theme fonts: all \(families.count) available" : "Theme fonts missing (substituted): \(missing.joined(separator: ", "))")
        print("Snapshots written to \(dir.path)")
    }

    /// A theme on its design background: "dusk", "bright" (sky and sun) or "window" (a light app window).
    static func themeCard(_ theme: Theme, items: [WheelItem], hit: WheelHit, parent: Int?) -> some View {
        ZStack {
            DesignBackground(kind: theme.spec.preview ?? (theme.isDark ? "dusk" : "bright"))
            WheelCanvas(items: items, theme: theme, hit: hit, openParent: parent, opaqueBackdrop: true)
        }
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

/// The backgrounds the theme boards preview on.
struct DesignBackground: View {
    let kind: String

    var body: some View {
        switch kind {
        case "bright":
            GeometryReader { g in
                ZStack {
                    LinearGradient(stops: [.init(color: Color(hex: 0x8CC6F3), location: 0), .init(color: Color(hex: 0xD3EAFB), location: 0.54),
                                           .init(color: Color(hex: 0xF0D7A3), location: 0.55), .init(color: Color(hex: 0xE2BF7F), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                    Circle().fill(Color(hex: 0xFFF7D6))
                        .frame(width: g.size.width * 0.16, height: g.size.width * 0.16)
                        .blur(radius: 4)
                        .position(x: g.size.width * 0.76, y: g.size.height * 0.2)
                }
            }
        case "window":
            ZStack {
                Color(hex: 0xE8E8EB)
                RoundedRectangle(cornerRadius: 12).fill(.white).padding(40).shadow(color: .black.opacity(0.12), radius: 25, y: 20)
            }
        default:
            LinearGradient(colors: [Color(hex: 0x211743), Color(hex: 0x05091C)], startPoint: .top, endPoint: .bottom)
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
