import SwiftUI
import AppKit
import RingCore

enum Selection: Hashable {
    case item(UUID)
    case child(UUID, UUID)
}

struct ItemPath: Equatable {
    let item: Int
    let child: Int?
}

extension RingConfig {
    func path(of selection: Selection) -> ItemPath? {
        switch selection {
        case .item(let id):
            return items.firstIndex { $0.id == id }.map { ItemPath(item: $0, child: nil) }
        case .child(let pid, let cid):
            guard let i = items.firstIndex(where: { $0.id == pid }),
                  let j = items[i].children.firstIndex(where: { $0.id == cid }) else { return nil }
            return ItemPath(item: i, child: j)
        }
    }

    subscript(path: ItemPath) -> WheelItem {
        get { path.child.map { items[path.item].children[$0] } ?? items[path.item] }
        set {
            if let j = path.child { items[path.item].children[j] = newValue } else { items[path.item] = newValue }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @State var tab: Tab = .actions
    @State private var selection: Selection?

    enum Tab: String, CaseIterable {
        case actions = "Actions"
        case general = "General"
    }

    var body: some View {
        HStack(spacing: 0) {
            WheelPreviewPane(store: store, selection: $selection, tab: $tab)
                .frame(width: 380)
            Divider()
            VStack(spacing: 0) {
                TabSwitcher(tab: $tab)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                Divider()
                switch tab {
                case .actions: ActionsPane(store: store, selection: $selection)
                case .general: GeneralPane(store: store, launchAtLogin: launchAtLogin)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 900, minHeight: 580)
        .onAppear {
            if selection == nil, let first = store.config.items.first { selection = .item(first.id) }
        }
    }
}

struct TabSwitcher: View {
    @Binding var tab: SettingsView.Tab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsView.Tab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { tab = t }
                } label: {
                    Text(t.rawValue)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(tab == t ? Color.primary : Color.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background {
                            if tab == t {
                                Capsule().fill(Color.primary.opacity(0.12))
                                    .matchedGeometryEffect(id: "tab", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Preview

struct WheelPreviewPane: View {
    @ObservedObject var store: ConfigStore
    @Binding var selection: Selection?
    @Binding var tab: SettingsView.Tab
    private let metrics = WheelMetrics.standard
    private let scale: CGFloat = 0.66

    var body: some View {
        let theme = Theme.named(store.config.theme)
        let state = previewState
        ZStack {
            LinearGradient(colors: theme.isDark
                           ? [Color(red: 0.13, green: 0.09, blue: 0.27), Color(red: 0.02, green: 0.04, blue: 0.11)]
                           : [Color(red: 0.95, green: 0.91, blue: 0.99), Color(red: 0.84, green: 0.91, blue: 0.99)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 14) {
                Spacer()
                WheelCanvas(items: store.config.items, theme: theme, hit: state.hit, openParent: state.parent,
                            opaqueBackdrop: true)
                    .contentShape(Rectangle())
                    .onTapGesture { location in select(at: location) }
                    .scaleEffect(scale)
                    .frame(width: metrics.canvasSize * scale, height: metrics.canvasSize * scale)
                Text("Click a slice to edit it")
                    .font(.callout)
                    .foregroundStyle(theme.subtext)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                    Text("Hold \(KeyCombo(store.config.hotkey)?.display ?? store.config.hotkey) anywhere")
                }
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(theme.text.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(theme.text.opacity(0.08)))
                .padding(.bottom, 22)
            }
        }
    }

    private var previewState: (hit: WheelHit, parent: Int?) {
        guard let selection, let path = store.config.path(of: selection) else { return (.center, nil) }
        if let j = path.child { return (.child(path.item, j), path.item) }
        let hasChildren = !store.config.items[path.item].children.isEmpty
        return (.item(path.item), hasChildren ? path.item : nil)
    }

    private func select(at location: CGPoint) {
        let s = metrics.canvasSize
        let geometry = WheelGeometry(childCounts: store.config.items.map(\.children.count), metrics: metrics)
        let items = store.config.items
        switch geometry.hit(dx: location.x - s / 2, dy: s / 2 - location.y, openParent: previewState.parent) {
        case .item(let i):
            selection = .item(items[i].id)
            tab = .actions
        case .child(let p, let j):
            selection = .child(items[p].id, items[p].children[j].id)
            tab = .actions
        case .center:
            tab = .general
        case .cancel:
            break
        }
    }
}

// MARK: - Actions tab

struct ActionsPane: View {
    @ObservedObject var store: ConfigStore
    @Binding var selection: Selection?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.config.items) { item in
                        SliceRow(item: item, isChild: false).tag(Selection.item(item.id))
                        ForEach(item.children) { child in
                            SliceRow(item: child, isChild: true).tag(Selection.child(item.id, child.id))
                        }
                    }
                }
                .listStyle(.sidebar)
                Divider()
                toolbar
            }
            .frame(width: 250)
            Divider()
            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            Button(action: addSlice) { Image(systemName: "plus") }
                .help("Add slice")
                .disabled(store.config.items.count >= RingConfig.maxItems)
            Button(action: addChild) { Image(systemName: "arrow.turn.down.right") }
                .help("Add sub-action to the selected slice")
                .disabled(!canAddChild)
            Button(action: deleteSelected) { Image(systemName: "minus") }
                .help("Delete")
                .disabled(selection == nil)
            Spacer()
            Button { move(by: -1) } label: { Image(systemName: "arrow.up") }
                .help("Move counter-clockwise / up")
            Button { move(by: 1) } label: { Image(systemName: "arrow.down") }
                .help("Move clockwise / down")
        }
        .buttonStyle(.borderless)
        .controlSize(.large)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var editor: some View {
        if let selection, let path = store.config.path(of: selection) {
            ItemEditor(item: binding(for: selection, fallback: store.config[path]),
                       isChild: path.child != nil,
                       parentLabel: path.child != nil ? store.config.items[path.item].label : nil)
                .id(selection)
        } else {
            ContentUnavailableView("Nothing selected", systemImage: "circle.circle",
                                   description: Text("Pick a slice in the list, or click one on the wheel."))
        }
    }

    private func binding(for selection: Selection, fallback: WheelItem) -> Binding<WheelItem> {
        Binding(
            get: { store.config.path(of: selection).map { store.config[$0] } ?? fallback },
            set: { newValue in
                guard let path = store.config.path(of: selection) else { return }
                store.config[path] = newValue
            }
        )
    }

    // MARK: Mutations

    private var selectedPath: ItemPath? { selection.flatMap { store.config.path(of: $0) } }

    private var canAddChild: Bool {
        guard let path = selectedPath else { return false }
        return store.config.items[path.item].children.count < RingConfig.maxChildren
    }

    private func addSlice() {
        let item = WheelItem(label: "New slice", action: .app(bundleId: ""))
        let index = selectedPath.map { $0.item + 1 } ?? store.config.items.count
        store.config.items.insert(item, at: index)
        selection = .item(item.id)
    }

    private func addChild() {
        guard let path = selectedPath else { return }
        let parent = store.config.items[path.item]
        let child = WheelItem(label: "New action", action: .keys("", bundleId: parent.action.bundleId))
        store.config.items[path.item].children.append(child)
        selection = .child(parent.id, child.id)
    }

    private func deleteSelected() {
        guard let path = selectedPath else { return }
        if let j = path.child {
            store.config.items[path.item].children.remove(at: j)
            let parent = store.config.items[path.item]
            let remaining = parent.children
            selection = remaining.isEmpty ? .item(parent.id) : .child(parent.id, remaining[min(j, remaining.count - 1)].id)
        } else {
            store.config.items.remove(at: path.item)
            let items = store.config.items
            selection = items.isEmpty ? nil : .item(items[min(path.item, items.count - 1)].id)
        }
    }

    private func move(by delta: Int) {
        guard let path = selectedPath else { return }
        if let j = path.child {
            let target = j + delta
            guard store.config.items[path.item].children.indices.contains(target) else { return }
            store.config.items[path.item].children.swapAt(j, target)
        } else {
            let target = path.item + delta
            guard store.config.items.indices.contains(target) else { return }
            store.config.items.swapAt(path.item, target)
        }
    }
}

struct SliceRow: View {
    let item: WheelItem
    let isChild: Bool

    var body: some View {
        HStack(spacing: 8) {
            IconView(icon: IconCache.shared.icon(for: item, isChild: isChild), size: isChild ? 16 : 20, tint: .secondary)
            Text(item.label.isEmpty ? "Untitled" : item.label)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.leading, isChild ? 20 : 0)
    }

    private var summary: String {
        switch item.action {
        case .app: return ""
        case .url: return "URL"
        case .keys(let k, _): return KeyCombo(k)?.display ?? "⌨︎"
        case .shell: return "sh"
        case .none: return ""
        }
    }
}

// MARK: - Item editor

struct ItemEditor: View {
    @Binding var item: WheelItem
    let isChild: Bool
    let parentLabel: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    IconView(icon: IconCache.shared.icon(for: item, isChild: isChild), size: 40, tint: .accentColor)
                        .frame(width: 56, height: 56)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isChild ? "Sub-action of \(parentLabel ?? "")" : "Slice")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("", text: $item.label, prompt: Text("Label"))
                            .labelsHidden()
                            .textFieldStyle(.plain)
                            .font(.title2.weight(.semibold))
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Action") {
                Picker("Type", selection: kind) {
                    ForEach(Action.Kind.allCases, id: \.self) { Text(Self.title(for: $0)).tag($0) }
                }
                .pickerStyle(.segmented)
                actionFields
            }

            Section("Icon") {
                IconPicker(icon: $item.icon)
            }

            if !isChild {
                Section {
                    Label {
                        Text("\(item.children.count) of \(RingConfig.maxChildren) sub-actions. They fan out around this slice when you hover it; letting go on the slice itself runs the action above. Add one with ↳ under the list.")
                    } icon: {
                        Image(systemName: "circle.circle")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var actionFields: some View {
        switch item.action.kind {
        case .app:
            AppPicker(title: "Application", bundleId: bundleId)
            Text("Brings the app to the front, launching it if needed.")
                .font(.caption).foregroundStyle(.secondary)
        case .url:
            TextField("URL or path", text: text, prompt: Text("https://…, slack://…, ~/Documents"))
            AppPicker(title: "Open with", bundleId: bundleId, noneLabel: "Default app")
        case .keys:
            LabeledContent("Shortcut") { KeyRecorder(combo: text) }
            AppPicker(title: "Send to", bundleId: bundleId, noneLabel: "Frontmost app")
            AccessibilityNote()
        case .shell:
            TextField("Command", text: text, prompt: Text("open -a iTerm ~/code"), axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .lineLimit(3...8)
            Text("Runs with /bin/zsh -lc in your home folder.")
                .font(.caption).foregroundStyle(.secondary)
        case .none:
            Text("Does nothing; useful for a slice that only groups sub-actions.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    static func title(for kind: Action.Kind) -> String {
        switch kind {
        case .app: "App"
        case .url: "URL"
        case .keys: "Shortcut"
        case .shell: "Shell"
        case .none: "None"
        }
    }

    // MARK: Bindings into the action enum

    private var kind: Binding<Action.Kind> {
        Binding(get: { item.action.kind }, set: { item.action = item.action.converted(to: $0) })
    }

    private var bundleId: Binding<String> {
        Binding(
            get: { item.action.bundleId ?? "" },
            set: { new in
                let value: String? = new.isEmpty ? nil : new
                switch item.action {
                case .app: item.action = .app(bundleId: new)
                case .url(let u, _): item.action = .url(u, bundleId: value)
                case .keys(let k, _): item.action = .keys(k, bundleId: value)
                default: break
                }
            })
    }

    private var text: Binding<String> {
        Binding(
            get: {
                switch item.action {
                case .url(let u, _): u
                case .keys(let k, _): k
                case .shell(let c): c
                default: ""
                }
            },
            set: { new in
                switch item.action {
                case .url(_, let b): item.action = .url(new, bundleId: b)
                case .keys(_, let b): item.action = .keys(new, bundleId: b)
                case .shell: item.action = .shell(new)
                default: break
                }
            })
    }
}

struct AccessibilityNote: View {
    @State private var trusted = ActionRunner.hasAccessibility

    var body: some View {
        Group {
            if !trusted {
                HStack {
                    Label("Sending shortcuts needs Accessibility permission.", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Grant…") { ActionRunner.requestAccessibility() }
                        .controlSize(.small)
                }
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            trusted = ActionRunner.hasAccessibility
        }
    }
}
