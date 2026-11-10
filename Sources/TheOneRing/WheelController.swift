import AppKit
import SwiftUI
import RingCore

/// Borderless, transparent, click-through panel that floats above everything (including
/// full-screen apps) and never takes focus away from the app you're in.
final class WheelPanel: NSPanel {
    init(size: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows the wheel under the cursor on hotkey press, follows the cursor, runs the action on release.
final class WheelController {
    var onOpenSettings: (() -> Void)?

    let model = WheelModel()
    private let panel: WheelPanel
    private var tracker = WheelTracker(geometry: WheelGeometry(childCounts: []))
    private var center: NSPoint = .zero
    private var timer: Timer?
    private var requiredModifiers: NSEvent.ModifierFlags = []
    private(set) var isOpen = false
    private let metrics = WheelMetrics.standard

    init() {
        panel = WheelPanel(size: metrics.canvasSize)
        let host = NSHostingView(rootView: LiveWheelView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: metrics.canvasSize, height: metrics.canvasSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        prewarm()
    }

    func apply(config: RingConfig) {
        model.items = config.items
        model.theme = Theme.named(config.theme)
        tracker = WheelTracker(geometry: WheelGeometry(childCounts: config.items.map(\.children.count), metrics: metrics))
        requiredModifiers = NSEvent.ModifierFlags(KeyCombo(config.hotkey)?.modifiers.map(\.eventFlag) ?? [])
        IconCache.shared.preload(config.items)
    }

    // MARK: Open / close

    func open() {
        guard !isOpen else { return } // ignore key auto-repeat
        isOpen = true

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

        let half = metrics.canvasSize / 2
        panel.setFrame(NSRect(x: center.x - half, y: center.y - half, width: half * 2, height: half * 2), display: false)
        tracker.reset()
        model.hit = .center
        model.openParent = nil
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
        guard isOpen else { return }
        tick(checkModifiers: false)
        let hit = model.hit
        close()
        switch hit {
        case .center:
            onOpenSettings?()
        case .item(let i) where i < model.items.count:
            ActionRunner.run(model.items[i].action)
        case .child(let p, let j) where p < model.items.count && j < model.items[p].children.count:
            ActionRunner.run(model.items[p].children[j].action)
        default:
            break
        }
    }

    func cancel() {
        guard isOpen else { return }
        close()
    }

    private func close() {
        isOpen = false
        timer?.invalidate()
        timer = nil
        HotkeyManager.shared.setEscapeEnabled(false)
        model.visible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.09
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isOpen else { return }
            self.panel.orderOut(nil)
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
