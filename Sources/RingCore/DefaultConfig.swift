import Foundation

public enum DefaultConfig {
    public enum BundleID {
        // Built into macOS.
        public static let safari = "com.apple.Safari"
        public static let mail = "com.apple.mail"
        public static let calendar = "com.apple.iCal"
        public static let notes = "com.apple.Notes"
        public static let terminal = "com.apple.Terminal"
        public static let systemSettings = "com.apple.systempreferences"
        // Used by the showcase wheel.
        public static let dia = "company.thebrowser.dia"
        public static let slack = "com.tinyspeck.slackmacgap"
        public static let outlook = "com.microsoft.Outlook"
        /// Ostraka, installed as a Chrome web app.
        public static let ostraka = "com.google.Chrome.app.dekblognmjndkkfcbifaddddgaplkgbn"
        public static let finder = "com.apple.finder"
        public static let claude = "com.anthropic.claudefordesktop"
        public static let cursor = "com.todesktop.230313mzl4w4u92"
        public static let iterm = "com.googlecode.iterm2"
        public static let figma = "com.figma.Desktop"
    }

    private static func keys(_ label: String, _ symbol: String, _ combo: String, _ app: String) -> WheelItem {
        WheelItem(label: label, icon: "sf:\(symbol)", action: .keys(combo, bundleId: app))
    }

    /// What a new install starts with: apps that come with macOS, clockwise from the top.
    /// The app writes it to config.json on first launch, minus anything not installed
    /// (see `keepingInstalled`).
    public static var config: RingConfig {
        typealias B = BundleID
        return RingConfig(items: [
            WheelItem(label: "Safari", action: .app(bundleId: B.safari), children: [
                keys("New tab", "plus.square.on.square", "cmd+t", B.safari),
                keys("New window", "macwindow.badge.plus", "cmd+n", B.safari),
                keys("Private window", "eye.slash", "cmd+shift+n", B.safari),
            ]),
            WheelItem(label: "Mail", action: .app(bundleId: B.mail), children: [
                keys("New message", "square.and.pencil", "cmd+n", B.mail),
                keys("Get mail", "tray.and.arrow.down", "cmd+shift+n", B.mail),
            ]),
            WheelItem(label: "Calendar", action: .app(bundleId: B.calendar), children: [
                keys("New event", "calendar.badge.plus", "cmd+n", B.calendar),
                keys("Today", "calendar", "cmd+t", B.calendar),
            ]),
            WheelItem(label: "Finder", action: .app(bundleId: B.finder), children: [
                WheelItem(label: "Downloads", icon: "sf:arrow.down.circle", action: .url("~/Downloads", bundleId: nil)),
                WheelItem(label: "Home", icon: "sf:house", action: .url("~", bundleId: nil)),
                WheelItem(label: "Applications", icon: "sf:square.grid.2x2", action: .url("/Applications", bundleId: nil)),
            ]),
            screenshot,
            WheelItem(label: "Notes", action: .app(bundleId: B.notes), children: [
                keys("New note", "square.and.pencil", "cmd+n", B.notes),
            ]),
            WheelItem(label: "Terminal", action: .app(bundleId: B.terminal), children: [
                keys("New window", "macwindow.badge.plus", "cmd+n", B.terminal),
                keys("New tab", "plus.square.on.square", "cmd+t", B.terminal),
            ]),
            WheelItem(label: "System Settings", action: .app(bundleId: B.systemSettings)),
        ])
    }

    /// `config` without the slices and sub-actions whose app isn't installed.
    public static func keepingInstalled(_ config: RingConfig, isInstalled: (String) -> Bool) -> RingConfig {
        func available(_ item: WheelItem) -> Bool { item.action.bundleId.map(isInstalled) ?? true }
        var config = config
        config.items = config.items.filter(available).map { item in
            var item = item
            item.children = item.children.filter(available)
            return item
        }
        return config
    }

    // macOS's own screenshot shortcuts: saved where you've set, no extra permission needed.
    private static var screenshot: WheelItem {
        WheelItem(label: "Screenshot", icon: "sf:camera.viewfinder", action: .keys("cmd+shift+4", bundleId: nil), children: [
            WheelItem(label: "Zone", icon: "sf:rectangle.dashed", action: .keys("cmd+shift+4", bundleId: nil)),
            WheelItem(label: "Full screen", icon: "sf:display", action: .keys("cmd+shift+3", bundleId: nil)),
            WheelItem(label: "Video", icon: "sf:record.circle", action: .keys("cmd+shift+5", bundleId: nil)),
        ])
    }

    /// A full ten-slice wheel with third-party apps and a prompt action. Used for the snapshots and the
    /// README banner, and saved as examples/config.json. Clockwise from the top.
    public static var showcase: RingConfig {
        typealias B = BundleID
        return RingConfig(items: [
            WheelItem(label: "Dia", action: .app(bundleId: B.dia), children: [
                keys("New tab", "plus.square.on.square", "cmd+t", B.dia),
                keys("New window", "macwindow.badge.plus", "cmd+n", B.dia),
            ]),
            WheelItem(label: "Ostraka", action: .app(bundleId: B.ostraka), children: [
                WheelItem(label: "Quick todo", icon: "sf:checklist",
                          action: .prompt(command: "ostraka todo add \"$1\"",
                                          placeholder: "Review the board #tag *high ^fri")),
            ]),
            WheelItem(label: "Slack", action: .app(bundleId: B.slack), children: [
                keys("Jump to…", "magnifyingglass", "cmd+k", B.slack),
                keys("Threads", "bubble.left.and.bubble.right", "cmd+shift+t", B.slack),
            ]),
            WheelItem(label: "Outlook", action: .app(bundleId: B.outlook), children: [
                keys("New email", "square.and.pencil", "cmd+n", B.outlook),
                keys("Mail", "tray", "cmd+1", B.outlook),
                keys("Calendar", "calendar", "cmd+2", B.outlook),
            ]),
            WheelItem(label: "Finder", action: .app(bundleId: B.finder), children: [
                WheelItem(label: "Downloads", icon: "sf:arrow.down.circle", action: .url("~/Downloads", bundleId: nil)),
                WheelItem(label: "Home", icon: "sf:house", action: .url("~", bundleId: nil)),
            ]),
            screenshot,
            WheelItem(label: "Figma", action: .app(bundleId: B.figma)),
            WheelItem(label: "iTerm", action: .app(bundleId: B.iterm), children: [
                keys("New window", "macwindow.badge.plus", "cmd+n", B.iterm),
                keys("New tab", "plus.square.on.square", "cmd+t", B.iterm),
            ]),
            WheelItem(label: "Claude", action: .app(bundleId: B.claude), children: [
                keys("New chat", "plus.bubble", "cmd+n", B.claude),
            ]),
            WheelItem(label: "Cursor", action: .app(bundleId: B.cursor), children: [
                keys("New window", "macwindow.badge.plus", "cmd+shift+n", B.cursor),
                keys("Open recent", "clock.arrow.circlepath", "ctrl+r", B.cursor),
            ]),
        ])
    }
}
