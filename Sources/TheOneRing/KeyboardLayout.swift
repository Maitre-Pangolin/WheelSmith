import Carbon.HIToolbox
import RingCore

/// Maps characters to virtual key codes using the *current* keyboard layout, so "cmd+a" sends the
/// key labelled A whether you type on QWERTY, AZERTY or anything else.
enum KeyboardLayout {
    static func keyCode(for key: String) -> UInt16? {
        if let code = KeyNames.named[key] { return code }
        return characterMap()[key.lowercased()]
    }

    /// Name for a recorded key code: a named key ("space", "f5") or the character it types.
    static func name(forKeyCode code: UInt16) -> String? {
        if let named = KeyNames.name(forKeyCode: code) { return named }
        return translate(code)
    }

    private static func characterMap() -> [String: UInt16] {
        var map: [String: UInt16] = [:]
        for code in UInt16(0)..<128 {
            if let s = translate(code), map[s] == nil { map[s] = code }
        }
        return map
    }

    private static func translate(_ code: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            let s = String(utf16CodeUnits: chars, count: length).lowercased()
            return s.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).isEmpty ? nil : s
        }
    }
}
