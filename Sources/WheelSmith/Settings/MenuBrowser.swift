import SwiftUI
import AppKit
import RingCore

/// Loads an app's menu-bar commands for the browser sheet.
final class MenuBrowserModel: ObservableObject {
    enum State {
        case loading
        case needsPermission
        case notRunning
        case notInstalled
        case empty
        case loaded([MenuCommand])
    }

    @Published private(set) var state: State = .loading
    let bundleId: String
    private let preset: [MenuCommand]?

    /// `preset` skips the live scan (used by the snapshot renderer).
    init(bundleId: String, preset: [MenuCommand]? = nil) {
        self.bundleId = bundleId
        self.preset = preset
        if let preset { state = .loaded(preset) }
    }

    func load() {
        if preset != nil { return }
        guard ActionRunner.hasAccessibility else { state = .needsPermission; return }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            state = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) == nil ? .notInstalled : .notRunning
            return
        }
        state = .loading
        let pid = app.processIdentifier
        DispatchQueue.global(qos: .userInitiated).async {
            let commands = MenuBar.commands(pid: pid)
            DispatchQueue.main.async {
                self.state = commands.isEmpty ? .empty : .loaded(commands)
            }
        }
    }

    /// Menus only exist while an app runs: launch it in the background, then scan.
    func launchAndLoad() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        state = .loading
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        let deadline = Date().addingTimeInterval(15)
        func check() {
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
            if app?.isFinishedLaunching == true {
                // Give it a moment to build its menus.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.load() }
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: check)
            } else {
                load()
            }
        }
        check()
    }
}

struct MenuBrowserSheet: View {
    enum Mode {
        case pickOne
        case addMany(limit: Int)
    }

    let bundleId: String
    let mode: Mode
    let onDone: ([MenuCommand]) -> Void

    @StateObject private var model: MenuBrowserModel
    @State private var query = ""
    @State private var chosen: [MenuCommand] = []
    @Environment(\.dismiss) private var dismiss

    init(bundleId: String, mode: Mode, preset: [MenuCommand]? = nil, onDone: @escaping ([MenuCommand]) -> Void) {
        self.bundleId = bundleId
        self.mode = mode
        self.onDone = onDone
        _model = StateObject(wrappedValue: MenuBrowserModel(bundleId: bundleId, preset: preset))
    }

    private var appName: String { AppCatalog.shared.name(for: bundleId) ?? bundleId }
    private var isSingle: Bool { if case .pickOne = mode { true } else { false } }
    private var limit: Int { if case .addMany(let n) = mode { n } else { 1 } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 580, height: 620)
        .onAppear { model.load() }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            // Pick up a freshly granted Accessibility permission without reopening the sheet.
            if case .needsPermission = model.state, ActionRunner.hasAccessibility { model.load() }
        }
    }

    // MARK: Header & footer

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if let icon = IconCache.shared.appIcon(bundleId) {
                    Image(nsImage: icon).resizable().frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isSingle ? "Choose a \(appName) menu command" : "Add \(appName) menu commands")
                        .font(.headline)
                    Text(isSingle ? "The wheel clicks it for you after bringing \(appName) forward."
                                  : "Each one becomes a sub-action around the slice (up to \(limit) more).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Read the menus again")
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search commands or shortcuts", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Text(footerText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isSingle ? "Use" : (chosen.isEmpty ? "Add" : "Add \(chosen.count)")) {
                onDone(chosen)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(chosen.isEmpty)
        }
        .padding(16)
    }

    private var footerText: String {
        if isSingle { return chosen.first.map { MenuPath.display($0.path) } ?? "Nothing selected" }
        return "\(chosen.count) of \(limit) selected"
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Reading \(appName)'s menus…")
        case .needsPermission:
            ContentUnavailableView {
                Label("Accessibility needed", systemImage: "lock.shield")
            } description: {
                Text("WheelSmith reads and clicks other apps' menus through Accessibility. Grant it, and this list loads by itself.")
            } actions: {
                Button("Grant Accessibility…") { ActionRunner.requestAccessibility() }
            }
        case .notRunning:
            ContentUnavailableView {
                Label("\(appName) isn't running", systemImage: "moon.zzz")
            } description: {
                Text("Apps only have menus while they're open.")
            } actions: {
                Button("Launch \(appName) in the background") { model.launchAndLoad() }
            }
        case .notInstalled:
            ContentUnavailableView("\(appName) isn't installed", systemImage: "questionmark.app")
        case .empty:
            ContentUnavailableView("No menu commands found", systemImage: "filemenu.and.selection",
                                   description: Text("\(appName) didn't report any menus. Try ↻ once it has a window open."))
        case .loaded(let commands):
            list(commands)
        }
    }

    private func list(_ commands: [MenuCommand]) -> some View {
        let filtered = commands.filter { MenuPath.search(query, path: $0.path, shortcut: $0.shortcut) }
        var tops: [String] = []
        for c in filtered where !tops.contains(c.path[0]) { tops.append(c.path[0]) }
        return Group {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    ForEach(tops, id: \.self) { top in
                        Section(top) {
                            ForEach(filtered.filter { $0.path[0] == top }) { row($0) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func row(_ command: MenuCommand) -> some View {
        let isChosen = chosen.contains(command)
        return Button {
            toggle(command)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isChosen ? (isSingle ? "largecircle.fill.circle" : "checkmark.circle.fill") : "circle")
                    .foregroundStyle(isChosen ? Color.accentColor : Color.secondary)
                    .font(.system(size: 15))
                Image(systemName: MenuPath.symbol(for: command.path))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(MenuPath.label(for: command.path))
                    let trail = Array(command.path.dropFirst().dropLast())
                    if !trail.isEmpty, !(trail.count == 1 && MenuPath.matches(trail[0], MenuPath.label(for: command.path))) {
                        Text(MenuPath.display(trail))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let shortcut = command.shortcut {
                    Text(shortcut)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .opacity(command.enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .help(command.enabled ? MenuPath.display(command.path)
                              : "Greyed out in \(appName) right now (for example, no window is open). It may still work later.")
    }

    private func toggle(_ command: MenuCommand) {
        if isSingle {
            chosen = [command]
        } else if let i = chosen.firstIndex(of: command) {
            chosen.remove(at: i)
        } else if chosen.count < limit {
            chosen.append(command)
        } else {
            NSSound.beep()
        }
    }
}
