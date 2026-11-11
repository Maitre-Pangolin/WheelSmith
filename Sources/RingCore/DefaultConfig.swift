import Foundation

public enum DefaultConfig {
    public enum BundleID {
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

    /// Clockwise from the top.
    public static var config: RingConfig {
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
            // macOS's own screenshot shortcuts: saved where you've set, no extra permission needed.
            WheelItem(label: "Screenshot", icon: "sf:camera.viewfinder", action: .keys("cmd+shift+4", bundleId: nil), children: [
                WheelItem(label: "Zone", icon: "sf:rectangle.dashed", action: .keys("cmd+shift+4", bundleId: nil)),
                WheelItem(label: "Full screen", icon: "sf:display", action: .keys("cmd+shift+3", bundleId: nil)),
                WheelItem(label: "Video", icon: "sf:record.circle", action: .keys("cmd+shift+5", bundleId: nil)),
            ]),
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
