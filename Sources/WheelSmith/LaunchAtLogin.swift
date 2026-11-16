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

    /// Only meaningful when running from an installed .app bundle (not `swift run`), and not from the
    /// random read-only copy macOS runs a freshly downloaded app from (App Translocation): a
    /// LaunchAgent pointing there would break as soon as that copy disappears.
    let isAvailable: Bool
    let isTranslocated: Bool

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
    }

    init() {
        isTranslocated = Bundle.main.bundlePath.contains("/AppTranslocation/")
        isAvailable = Bundle.main.bundleURL.pathExtension == "app" && !isTranslocated
        isEnabled = FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.label).plist").path)
    }

    /// Turn it on automatically the first time the installed app runs, and keep the LaunchAgent
    /// pointing at this copy if the app was moved since it was written.
    func enableOnFirstRun() {
        guard isAvailable else { return }
        let key = "didOfferLaunchAtLogin"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            if !isEnabled { isEnabled = true; return }
        }
        if isEnabled, registeredExecutable != Bundle.main.executablePath { install() }
    }

    private var registeredExecutable: String? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let args = plist["ProgramArguments"] as? [String] else { return nil }
        return args.first
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
