import AppKit
import SwiftUI
import RingCore

/// Borderless, transparent, click-through panel that floats above everything (including
/// full-screen apps) and never takes focus away from the app you're in.
final class WheelPanel: NSPanel {
    init(size: CGSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    /// Only while a Prompt action waits for text. Being a non-activating panel, it takes the keyboard
    /// without activating WheelSmith, so the app you were in stays frontmost.
    var acceptsKeyboard = false
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }

    /// Escape from the text field (the Escape hotkey normally catches it first).
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// Shows the wheel under the cursor on hotkey press, follows the cursor, runs the action on release.
final class WheelController {
    /// How long the wheel must be open before letting go in the center opens Settings. A quick
    /// press-and-release in the center just closes it.
    static let settingsDelay: TimeInterval = 1.0

    var onOpenSettings: (() -> Void)?

    let model = WheelModel()
    private let panel: WheelPanel
    private var tracker = WheelTracker(geometry: WheelGeometry(childCounts: []))
    private var center: NSPoint = .zero
    private var timer: Timer?
    private var requiredModifiers: NSEvent.ModifierFlags = []
    private(set) var isOpen = false
    private let metrics = WheelMetrics.standard
    /// Display arrangement captured when the wheel opened.
    private var layout: DisplayLayout?
    /// Bumped on every open, so late window lists from a previous open are ignored.
    private var openGeneration = 0
    /// Command of the Prompt action waiting for text, while the wheel stays open for typing.
    private var promptCommand: String?
    /// The app we activated to get the keyboard, if the panel couldn't take it on its own.
    private var appToRestore: NSRunningApplication?
    /// Bumped on every close, so a prompt command finishing later doesn't touch a newer wheel.
    private var closeGeneration = 0

    init() {
        panel = WheelPanel(size: Stage.size(metrics))
        let host = NSHostingView(rootView: LiveWheelView(model: model))
        host.frame = NSRect(origin: .zero, size: Stage.size(metrics))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.onEscape = { [weak self] in self?.cancel() }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) {
            [weak self] _ in self?.promptLostFocus()
        }
        prewarm()
    }

    func apply(config: RingConfig) {
        model.items = config.items
        model.theme = Theme.named(config.theme)
        tracker = WheelTracker(geometry: ringGeometry(windows: [:]))
        requiredModifiers = NSEvent.ModifierFlags(KeyCombo(config.hotkey)?.modifiers.map(\.eventFlag) ?? [])
        IconCache.shared.preload(config.items)
        Windows.watch(bundleIds: config.items.compactMap {
            if case .app(let id) = $0.action, !id.isEmpty { id } else { nil }
        })
    }

    // MARK: Open / close

    func open() {
        guard !isOpen else { return } // ignore key auto-repeat
        isOpen = true
        model.prompt = nil

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        center = mouse
        if let frame = screen?.visibleFrame {
            // Keep the whole slice ring on screen; if we had to shift, move the pointer to the center.
            let margin = metrics.ringOuter + 16
            center.x = min(max(mouse.x, frame.minX + margin), frame.maxX - margin)
            center.y = min(max(mouse.y, frame.minY + margin), frame.maxY - margin)
            if center != mouse { warpPointer(to: center) }
        }

        let stage = Stage.size(metrics)
        panel.setFrame(NSRect(x: center.x - stage.width / 2, y: center.y - stage.height / 2,
                              width: stage.width, height: stage.height), display: false)
        let layout = DisplayLayout.current()
        self.layout = layout
        model.hereDisplay = layout.index(containing: center)
        model.displayCount = layout.count
        model.windows = [:]
        tracker.geometry = ringGeometry(windows: [:])
        tracker.reset()
        model.hit = .center
        model.openParent = nil
        model.settingsArmed = false
        let generation = closeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settingsDelay) { [weak self] in
            guard let self, self.isOpen, generation == self.closeGeneration, self.model.prompt == nil else { return }
            self.model.settingsArmed = true
        }
        loadWindows(layout: layout)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        // Flip on the next runloop pass so SwiftUI animates the pop-in from the hidden state.
        DispatchQueue.main.async { [weak self] in
            if self?.isOpen == true { self?.model.visible = true }
        }

        HotkeyManager.shared.setEscapeEnabled(true)
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Hotkey released: run whatever is under the pointer.
    func release() {
        guard isOpen, model.prompt == nil else { return }
        tick(checkModifiers: false)
        let hit = model.hit
        let settingsArmed = model.settingsArmed
        if let (item, parent) = promptItem(at: hit), case .prompt(let command, let placeholder) = item.action {
            beginPrompt(item, parent: parent, command: command, placeholder: placeholder)
            return
        }
        close()
        switch hit {
        case .center:
            if settingsArmed { onOpenSettings?() }
        case .cancel:
            break
        case .item(let i) where i < model.items.count:
            let item = model.items[i]
            ActionRunner.run(item.action, context: context(for: item))
        case .child(let p, let j) where p < model.items.count:
            let parent = model.items[p]
            let ring = Ring(item: parent, windows: model.windows[p] ?? [])
            guard j < ring.count else { break }
            switch ring.entries[j] {
            case .window(let window):
                if let bundleId = parent.action.bundleId {
                    ActionRunner.focus(window: window, of: bundleId, context: context(for: parent))
                }
            case .action(let child):
                ActionRunner.run(child.action, context: context(for: parent))
            }
        default:
            break
        }
    }

    // MARK: Prompt

    /// The Prompt action under the pointer, with its parent slice when it's a sub-action.
    private func promptItem(at hit: WheelHit) -> (WheelItem, WheelItem?)? {
        switch hit {
        case .item(let i) where i < model.items.count:
            let item = model.items[i]
            return item.action.kind == .prompt ? (item, nil) : nil
        case .child(let p, let j) where p < model.items.count:
            let parent = model.items[p]
            let ring = Ring(item: parent, windows: model.windows[p] ?? [])
            guard j < ring.count, case .action(let child) = ring.entries[j], child.action.kind == .prompt else { return nil }
            return (child, parent)
        default:
            return nil
        }
    }

    /// Keeps the wheel open with a text field: Return runs the command with the text, Escape quits.
    private func beginPrompt(_ item: WheelItem, parent: WheelItem?, command: String, placeholder: String?) {
        timer?.invalidate() // stop following the pointer; the highlighted sub-action stays as it is
        timer = nil
        promptCommand = command
        let prompt = PromptModel(title: item.label, caption: parent?.label, placeholder: placeholder, theme: model.theme)
        prompt.icon = IconCache.shared.icon(for: item, isChild: parent != nil)
        prompt.onSubmit = { [weak self] in self?.submitPrompt() }
        model.promptOffset = promptOffset()
        model.prompt = prompt

        panel.acceptsKeyboard = true
        panel.ignoresMouseEvents = false
        panel.makeKeyAndOrderFront(nil)
        if !panel.isKeyWindow {
            // Fallback: activate WheelSmith to get the keyboard, and hand focus back when done.
            appToRestore = NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// To the right of the wheel, clear of the open sub-actions; on the left when the screen edge is too close.
    private func promptOffset() -> CGFloat {
        let width = PromptCard.width
        func inset(_ side: Double) -> CGFloat {
            CGFloat(tracker.geometry.horizontalClearance(halfHeight: Stage.promptHalfHeight,
                                                         openParent: model.openParent, side: side)) + Stage.promptGap
        }
        let right = inset(1), left = inset(-1)
        let screen = (NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) } ?? NSScreen.main)?.visibleFrame
        let fitsRight = screen.map { center.x + right + width <= $0.maxX - 8 } ?? true
        let fitsLeft = screen.map { center.x - left - width >= $0.minX + 8 } ?? false
        return fitsRight || !fitsLeft ? right + width / 2 : -(left + width / 2)
    }

    private func submitPrompt() {
        guard let prompt = model.prompt, let command = promptCommand, prompt.status != .running else { return }
        let text = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        prompt.status = .running
        let generation = closeGeneration
        PromptRunner.run(command, argument: text) { [weak self] ok, output in
            guard let self, generation == self.closeGeneration, self.model.prompt === prompt else { return }
            if ok {
                prompt.status = .done(output.first ?? "Done")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    if generation == self.closeGeneration { self.close() }
                }
            } else {
                NSSound.beep()
                prompt.status = .failed(output.last ?? "The command failed")
            }
        }
    }

    /// Clicking another app while typing quits the prompt (not while the command is running).
    private func promptLostFocus() {
        guard isOpen, let prompt = model.prompt, prompt.status != .running else { return }
        close()
    }

    // MARK: Windows

    private func context(for item: WheelItem) -> ActionContext {
        ActionContext(layout: layout, displayIndex: model.hereDisplay, bringHere: item.bringHere)
    }

    private func ringGeometry(windows: [Int: [WindowInfo]]) -> WheelGeometry {
        WheelGeometry(childCounts: model.items.indices.map { Ring(item: model.items[$0], windows: windows[$0] ?? []).count },
                      metrics: metrics)
    }

    /// Reads the open windows of every app slice in the background; the ring updates when they arrive
    /// (normally within a frame or two, well before you reach the outer ring).
    private func loadWindows(layout: DisplayLayout) {
        guard ActionRunner.hasAccessibility else { return }
        openGeneration += 1
        let generation = openGeneration
        let targets: [(Int, String)] = model.items.enumerated().compactMap { i, item in
            if case .app(let id) = item.action, !id.isEmpty { return (i, id) } else { return nil }
        }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            var found: [Int: [WindowInfo]] = [:]
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: targets.count) { k in
                let (index, bundleId) = targets[k]
                let windows = Windows.list(bundleId: bundleId, layout: layout)
                lock.lock(); found[index] = windows; lock.unlock()
            }
            DispatchQueue.main.async {
                guard let self, self.isOpen, generation == self.openGeneration else { return }
                self.model.windows = found
                self.tracker.geometry = self.ringGeometry(windows: found)
            }
        }
    }

    func cancel() {
        guard isOpen else { return }
        close()
    }

    private func close() {
        isOpen = false
        closeGeneration += 1
        model.settingsArmed = false
        timer?.invalidate()
        timer = nil
        HotkeyManager.shared.setEscapeEnabled(false)
        model.visible = false
        let hadPrompt = model.prompt != nil
        promptCommand = nil
        panel.acceptsKeyboard = false
        panel.ignoresMouseEvents = true
        if let app = appToRestore {
            appToRestore = nil
            app.activate()
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.09
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isOpen else { return }
            self.panel.orderOut(nil)
            if hadPrompt { self.model.prompt = nil }
        })
    }

    // MARK: Tracking

    private func tick(checkModifiers: Bool = true) {
        // Letting go of ⌥ counts as releasing the hotkey, even if Space is still down.
        if checkModifiers, !requiredModifiers.isEmpty,
           !NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).isSuperset(of: requiredModifiers) {
            release()
            return
        }
        let mouse = NSEvent.mouseLocation
        let hit = tracker.update(dx: mouse.x - center.x, dy: mouse.y - center.y)
        if hit != model.hit {
            model.hit = hit
            if case .item = hit { haptic() } else if case .child = hit { haptic() }
        }
        if tracker.openParent != model.openParent { model.openParent = tracker.openParent }
    }

    private func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func warpPointer(to point: NSPoint) {
        // CoreGraphics uses a top-left origin on the primary display.
        guard let primary = NSScreen.screens.first else { return }
        CGWarpMouseCursorPosition(CGPoint(x: point.x, y: primary.frame.maxY - point.y))
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// Render once off-screen at launch so the first real open is instant.
    private func prewarm() {
        panel.alphaValue = 0
        panel.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.display()
        panel.orderOut(nil)
    }
}
