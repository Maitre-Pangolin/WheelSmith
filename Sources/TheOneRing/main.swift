import AppKit

let arguments = CommandLine.arguments

// `TheOneRing --snapshot <dir>` renders the wheel and settings UI to PNGs and exits (for design review / CI).
if let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count {
    MainActor.assumeIsolated { Snapshot.run(outputDirectory: arguments[i + 1]) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar only: no Dock icon, no Cmd-Tab entry
app.run()
