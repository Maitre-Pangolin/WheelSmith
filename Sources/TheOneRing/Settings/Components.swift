import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RingCore

// MARK: - App picker

struct AppInfo: Identifiable, Hashable {
    var id: String { bundleId }
    let name: String
    let bundleId: String
    let url: URL
}

/// Installed apps, scanned once on first use.
final class AppCatalog {
    static let shared = AppCatalog()

    lazy var apps: [AppInfo] = {
        let fm = FileManager.default
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications",
                    "/System/Applications/Utilities", fm.homeDirectoryForCurrentUser.path + "/Applications"]
        var seen = Set<String>()
        var result: [AppInfo] = []
        for dir in dirs {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where name.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
                guard let id = Bundle(url: url)?.bundleIdentifier, seen.insert(id).inserted else { continue }
                result.append(AppInfo(name: String(name.dropLast(4)), bundleId: id, url: url))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    func name(for bundleId: String) -> String? {
        if let app = apps.first(where: { $0.bundleId == bundleId }) { return app.name }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return url.deletingPathExtension().lastPathComponent
    }

    func smallIcon(for url: URL) -> NSImage {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 16, height: 16)
        return img
    }
}

struct AppPicker: View {
    let title: String
    @Binding var bundleId: String
    /// Non-nil when "no app" is a valid choice.
    var noneLabel: String?

    var body: some View {
        LabeledContent(title) {
            Menu {
                if let noneLabel {
                    Button(noneLabel) { bundleId = "" }
                    Divider()
                }
                ForEach(AppCatalog.shared.apps) { app in
                    Button {
                        bundleId = app.bundleId
                    } label: {
                        Label { Text(app.name) } icon: { Image(nsImage: AppCatalog.shared.smallIcon(for: app.url)) }
                    }
                }
                Divider()
                Button("Choose…", action: choose)
            } label: {
                Text(currentName)
            }
            .fixedSize()
        }
    }

    private var currentName: String {
        if bundleId.isEmpty { return noneLabel ?? "Choose an app…" }
        return AppCatalog.shared.name(for: bundleId) ?? "\(bundleId) (not installed)"
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
            bundleId = id
        }
    }
}

// MARK: - Shortcut recorder

struct KeyRecorder: View {
    @Binding var combo: String
    /// The wheel hotkey: suspends the live hotkey while recording and requires a modifier.
    var isHotkey = false
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(label)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(minWidth: 110)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .onDisappear(perform: stop)
    }

    private var label: String {
        if recording { return "Type shortcut…" }
        if combo.isEmpty { return "Record shortcut" }
        return KeyCombo(combo)?.display ?? "⚠︎ \(combo)"
    }

    private func start() {
        recording = true
        if isHotkey { HotkeyManager.shared.suspend() }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = KeyCombo.Modifier.from(event.modifierFlags)
            if event.keyCode == 53, mods.isEmpty { // Esc cancels
                stop()
                return nil
            }
            guard let key = KeyboardLayout.name(forKeyCode: event.keyCode) else { NSSound.beep(); return nil }
            if isHotkey, mods.isEmpty, !key.hasPrefix("f") {
                NSSound.beep() // a bare letter would make that key unusable everywhere
                return nil
            }
            combo = KeyCombo(key: key, modifiers: mods).string
            stop()
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isHotkey { HotkeyManager.shared.resume() }
    }
}

// MARK: - Icon picker

struct IconPicker: View {
    @Binding var icon: String?

    enum Mode: String, CaseIterable {
        case automatic = "Automatic"
        case symbol = "SF Symbol"
        case file = "Image"
    }

    private static let suggestions = [
        "terminal", "globe", "bubble.left.and.bubble.right", "envelope", "note.text", "folder",
        "sparkles", "bolt", "calendar", "magnifyingglass", "plus.square.on.square", "macwindow.badge.plus",
        "square.and.pencil", "house", "star", "gearshape",
    ]

    var body: some View {
        Picker("Source", selection: mode) {
            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)

        switch mode.wrappedValue {
        case .automatic:
            Text("Uses the app's icon, or a symbol for the action type.")
                .font(.caption).foregroundStyle(.secondary)
        case .symbol:
            TextField("Symbol name", text: symbolName, prompt: Text("e.g. terminal"))
                .font(.system(.body, design: .monospaced))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8), alignment: .leading, spacing: 6) {
                ForEach(Self.suggestions, id: \.self) { name in
                    Button {
                        icon = "sf:" + name
                    } label: {
                        Image(systemName: name)
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(symbolName.wrappedValue == name ? Color.accentColor.opacity(0.25) : .clear))
                    }
                    .buttonStyle(.plain)
                    .help(name)
                }
            }
        case .file:
            HStack {
                Text(icon ?? "No file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…", action: chooseFile)
            }
        }
    }

    private var mode: Binding<Mode> {
        Binding(
            get: {
                guard let icon, !icon.isEmpty else { return .automatic }
                return icon.hasPrefix("sf:") ? .symbol : .file
            },
            set: { newMode in
                switch newMode {
                case .automatic: icon = nil
                case .symbol: if icon?.hasPrefix("sf:") != true { icon = "sf:star" }
                case .file: chooseFile()
                }
            })
    }

    private var symbolName: Binding<String> {
        Binding(get: { icon.map { String($0.dropFirst(3)) } ?? "" }, set: { icon = "sf:" + $0 })
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url { icon = url.path }
    }
}

// MARK: - General tab

struct GeneralPane: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @State private var confirmReset = false
    @State private var accessibility = ActionRunner.hasAccessibility

    var body: some View {
        Form {
            Section("Activation") {
                LabeledContent("Hotkey") { KeyRecorder(combo: $store.config.hotkey, isHotkey: true) }
                if let error = HotkeyManager.shared.registrationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Text("Hold the hotkey, point at a slice and let go. Let go in the center for Settings; beyond the edge, or press Esc, to cancel.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Theme") {
                HStack(spacing: 14) {
                    ForEach(Theme.all) { theme in
                        ThemeCard(theme: theme, items: store.config.items, selected: store.config.theme == theme.id) {
                            store.config.theme = theme.id
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("System") {
                Toggle("Launch at login, and restart if it ever crashes", isOn: $launchAtLogin.isEnabled)
                    .disabled(!launchAtLogin.isAvailable)
                if !launchAtLogin.isAvailable {
                    Text("Available when running the installed TheOneRing.app.").font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Accessibility") {
                    HStack {
                        Text(accessibility ? "Granted" : "Not granted")
                            .foregroundStyle(accessibility ? .green : .secondary)
                        if !accessibility { Button("Grant…") { ActionRunner.requestAccessibility() } }
                    }
                }
                Text("Only needed for Shortcut actions. App, URL and Shell actions work without it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Config file") {
                LabeledContent("Location") {
                    Text(store.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Open in Editor") { NSWorkspace.shared.open(store.url) }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.url]) }
                    Spacer()
                    Button("Reset to Defaults…", role: .destructive) { confirmReset = true }
                }
                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.red)
                }
                Text("Edits made here are saved instantly; edits to the file are picked up live.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset every slice to the defaults?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { store.resetToDefaults() }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            accessibility = ActionRunner.hasAccessibility
        }
    }
}

struct ThemeCard: View {
    let theme: Theme
    let items: [WheelItem]
    let selected: Bool
    let action: () -> Void
    private let scale: CGFloat = 0.2

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: theme.isDark
                                             ? [Color(red: 0.16, green: 0.11, blue: 0.32), Color(red: 0.03, green: 0.05, blue: 0.12)]
                                             : [Color(red: 0.96, green: 0.92, blue: 1.0), Color(red: 0.82, green: 0.9, blue: 1.0)],
                                             startPoint: .top, endPoint: .bottom))
                    WheelCanvas(items: items, theme: theme, hit: .item(0), openParent: nil,
                                opaqueBackdrop: true, showsHubHint: false)
                        .scaleEffect(scale * 1.6)
                        .frame(width: 130, height: 110)
                        .allowsHitTesting(false)
                }
                .frame(width: 130, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2.5 : 1))
                Text(theme.name)
                    .font(.callout.weight(selected ? .semibold : .regular))
            }
        }
        .buttonStyle(.plain)
    }
}
