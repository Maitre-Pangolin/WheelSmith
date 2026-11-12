import Foundation

/// "Always running": a per-user LaunchAgent that starts WheelSmith at login and restarts it if it crashes
/// (but not when you quit it from the menu — that's a clean exit).
final class LaunchAtLogin: ObservableObject {
    static let label = "dev.wheelsmith.app"

    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? install() : uninstall()
        }
    }

    /// Only meaningful when running from an installed .app bundle (not `swift run`).
    let isAvailable: Bool

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
    }

    init() {
        isAvailable = Bundle.main.bundleURL.pathExtension == "app"
        isEnabled = FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.label).plist").path)
    }

    /// Turn it on automatically the first time the installed app runs.
    func enableOnFirstRun() {
        let key = "didOfferLaunchAtLogin"
        guard isAvailable, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if !isEnabled { isEnabled = true }
    }

    private func install() {
        guard let executable = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            NSLog("WheelSmith: could not write LaunchAgent: \(error)")
        }
    }

    /// Removing the file is enough: launchd won't load it at next login. (We don't `bootout`,
    /// since that would kill this very process if launchd started it.)
    private func uninstall() {
        try? FileManager.default.removeItem(at: plistURL)
    }
}
