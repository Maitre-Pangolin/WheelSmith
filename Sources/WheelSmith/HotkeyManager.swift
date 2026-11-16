import Carbon.HIToolbox
import AppKit
import RingCore

/// Global hotkey via Carbon's RegisterEventHotKey.
/// Unlike a CGEventTap this needs NO Accessibility / Input Monitoring permission, and the key
/// presses are swallowed (the front app never sees ⌥Space).
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onEscape: (() -> Void)?
    /// An arrow key pressed while the wheel is open.
    var onArrow: ((Arrow) -> Void)?

    enum Arrow: UInt32, CaseIterable {
        case left, right, up, down

        var keyCode: Int {
            switch self {
            case .left: kVK_LeftArrow
            case .right: kVK_RightArrow
            case .up: kVK_UpArrow
            case .down: kVK_DownArrow
            }
        }
    }

    /// Non-nil when the last registration failed (e.g. another app owns the combo).
    private(set) var registrationError: String?

    private(set) var combo: KeyCombo?
    private var mainRef: EventHotKeyRef?
    private var escapeRefs: [EventHotKeyRef] = []
    private var arrowRefs: [EventHotKeyRef] = []
    private var suspended = false
    private let signature: OSType = 0x52_49_4E_47 // 'RING'

    private enum ID: UInt32 { case main = 1, escape = 2, escapeWithModifiers = 3 }
    /// Arrow hotkeys use ids from here up: base + arrow (bare) and base + 4 + arrow (with modifiers).
    private let arrowBase: UInt32 = 10

    private init() {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            manager.handle(id: hotKeyID.id, pressed: pressed)
            return noErr
        }, specs.count, &specs, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    /// Register (or re-register) the wheel hotkey. Returns false if it could not be registered.
    @discardableResult
    func setHotkey(_ combo: KeyCombo?) -> Bool {
        self.combo = combo
        return apply()
    }

    /// Temporarily release the hotkey (while recording a new one in Settings).
    func suspend() {
        suspended = true
        unregisterMain()
    }

    func resume() {
        suspended = false
        apply()
    }

    /// Esc cancels the wheel. Registered only while the wheel is open, both bare and with the
    /// hotkey's modifiers (you are usually still holding ⌥ when you press it).
    func setEscapeEnabled(_ enabled: Bool) {
        escapeRefs.forEach { UnregisterEventHotKey($0) }
        escapeRefs.removeAll()
        guard enabled else { return }
        let mods = carbonModifiers(combo?.modifiers ?? [])
        for (id, m) in [(ID.escape, UInt32(0)), (ID.escapeWithModifiers, mods)] where id == .escape || m != 0 {
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(UInt32(kVK_Escape), m, EventHotKeyID(signature: signature, id: id.rawValue),
                                   GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                escapeRefs.append(ref)
            }
        }
    }

    /// Arrows switch themes while the wheel is open. Registered like Esc, bare and with the hotkey's
    /// modifiers; off while a Prompt's text field needs them.
    func setArrowsEnabled(_ enabled: Bool) {
        arrowRefs.forEach { UnregisterEventHotKey($0) }
        arrowRefs.removeAll()
        guard enabled else { return }
        let mods = carbonModifiers(combo?.modifiers ?? [])
        for arrow in Arrow.allCases {
            for (offset, m) in [(UInt32(0), UInt32(0)), (UInt32(4), mods)] where offset == 0 || m != 0 {
                var ref: EventHotKeyRef?
                let id = EventHotKeyID(signature: signature, id: arrowBase + offset + arrow.rawValue)
                if RegisterEventHotKey(UInt32(arrow.keyCode), m, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                    arrowRefs.append(ref)
                }
            }
        }
    }

    // MARK: - Private

    @discardableResult
    private func apply() -> Bool {
        unregisterMain()
        guard !suspended, let combo else { return true }
        guard let code = KeyboardLayout.keyCode(for: combo.key) else {
            registrationError = "Unknown key “\(combo.key)”"
            return false
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(code), carbonModifiers(combo.modifiers),
                                         EventHotKeyID(signature: signature, id: ID.main.rawValue),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            mainRef = ref
            registrationError = nil
            return true
        }
        registrationError = status == eventHotKeyExistsErr
            ? "\(combo.display) is already used by another app"
            : "Could not register \(combo.display) (error \(status))"
        return false
    }

    private func unregisterMain() {
        if let mainRef { UnregisterEventHotKey(mainRef) }
        mainRef = nil
    }

    private func carbonModifiers(_ mods: [KeyCombo.Modifier]) -> UInt32 {
        mods.reduce(0) { acc, m in
            switch m {
            case .cmd: acc | UInt32(cmdKey)
            case .option: acc | UInt32(optionKey)
            case .control: acc | UInt32(controlKey)
            case .shift: acc | UInt32(shiftKey)
            }
        }
    }

    private func handle(id: UInt32, pressed: Bool) {
        if id >= arrowBase, id < arrowBase + 8 {
            if pressed, let arrow = Arrow(rawValue: (id - arrowBase) % 4) { onArrow?(arrow) }
            return
        }
        switch ID(rawValue: id) {
        case .main: pressed ? onPress?() : onRelease?()
        case .escape, .escapeWithModifiers: if pressed { onEscape?() }
        case nil: break
        }
    }
}

extension KeyCombo.Modifier {
    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .cmd: .command
        case .option: .option
        case .control: .control
        case .shift: .shift
        }
    }

    var cgFlag: CGEventFlags {
        switch self {
        case .cmd: .maskCommand
        case .option: .maskAlternate
        case .control: .maskControl
        case .shift: .maskShift
        }
    }

    static func from(_ flags: NSEvent.ModifierFlags) -> [KeyCombo.Modifier] {
        allCases.filter { flags.contains($0.eventFlag) }
    }
}
