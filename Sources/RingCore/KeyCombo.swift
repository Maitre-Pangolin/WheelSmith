import Foundation

/// A key plus modifiers, written as text like "cmd+shift+n" or "option+space".
/// Used both for the wheel hotkey and for "send shortcut" actions.
public struct KeyCombo: Equatable, Hashable, Sendable {
    public enum Modifier: String, CaseIterable, Sendable {
        case control, option, shift, cmd

        public var symbol: String {
            switch self {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .cmd: "⌘"
            }
        }

        static func parse(_ s: String) -> Modifier? {
            switch s {
            case "cmd", "command", "⌘", "meta", "super": .cmd
            case "opt", "option", "alt", "⌥": .option
            case "ctrl", "control", "⌃": .control
            case "shift", "⇧": .shift
            default: nil
            }
        }
    }

    /// Lowercased key name: a character ("n", "1", "/") or a named key ("space", "f13", "left").
    public var key: String
    /// Always kept in canonical order (⌃⌥⇧⌘).
    public private(set) var modifiers: [Modifier]

    public init(key: String, modifiers: [Modifier]) {
        self.key = key.lowercased()
        self.modifiers = Modifier.allCases.filter(modifiers.contains)
    }

    public init?(_ text: String) {
        let parts = text.lowercased()
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // "cmd++" means the plus key.
        var tokens = parts
        if text.hasSuffix("++") { tokens = Array(parts.dropLast(2)) + ["+"] }
        guard let last = tokens.last, !last.isEmpty else { return nil }
        var mods: [Modifier] = []
        for token in tokens.dropLast() {
            guard let m = Modifier.parse(token) else { return nil }
            mods.append(m)
        }
        let key = KeyNames.aliases[last] ?? last
        guard KeyNames.named[key] != nil || key.count == 1 else { return nil }
        self.init(key: key, modifiers: mods)
    }

    /// Canonical text form, e.g. "control+option+space".
    public var string: String {
        (modifiers.map { $0 == .cmd ? "cmd" : $0.rawValue } + [key]).joined(separator: "+")
    }

    /// Short display form, e.g. "⌥ Space" or "⌘⇧N".
    public var display: String {
        let mods = modifiers.map(\.symbol).joined()
        let k = KeyNames.display[key] ?? key.uppercased()
        return k.count > 1 ? "\(mods) \(k)".trimmingCharacters(in: .whitespaces) : mods + k
    }
}

/// Layout-independent keys (virtual key codes from HIToolbox/Events.h).
public enum KeyNames {
    public static let named: [String: UInt16] = [
        "space": 49, "return": 36, "enter": 76, "tab": 48, "escape": 53, "delete": 51,
        "forwarddelete": 117, "left": 123, "right": 124, "down": 125, "up": 126,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113,
        "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
        // Digits by position, so "cmd+1" works on AZERTY too.
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
    ]

    static let aliases: [String: String] = [
        "esc": "escape", "backspace": "delete", "del": "forwarddelete", "spacebar": "space",
        "pgup": "pageup", "pgdn": "pagedown", "arrowleft": "left", "arrowright": "right",
        "arrowup": "up", "arrowdown": "down",
    ]

    static let display: [String: String] = [
        "space": "Space", "return": "↩", "enter": "⌅", "tab": "⇥", "escape": "Esc", "delete": "⌫",
        "forwarddelete": "⌦", "left": "←", "right": "→", "up": "↑", "down": "↓",
        "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
    ]

    /// Reverse lookup for named keys (used when recording shortcuts).
    public static func name(forKeyCode code: UInt16) -> String? {
        named.first { $0.value == code && Int($0.key) == nil }?.key
    }
}
