import AppKit
import ApplicationServices
import RingCore

/// One clickable command found in an app's menu bar.
struct MenuCommand: Identifiable, Hashable {
    var id: String { path.joined(separator: "\u{1F}") }
    let path: [String]
    /// Display form, e.g. "⇧⌘T".
    let shortcut: String?
    let enabled: Bool
}

/// Reads and clicks other apps' menu bars through the Accessibility API.
/// Every Mac app exposes its menus this way, so this is the one "list of actions" all apps share.
/// Calls are synchronous IPC: run them off the main thread.
enum MenuBar {
    /// Menus whose contents are system boilerplate or change all the time.
    private static let skippedSubmenus: Set<String> = ["services", "open recent", "recent items", "recently closed"]

    static func commands(pid: pid_t, maxDepth: Int = 4) -> [MenuCommand] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.5)
        guard let bar = element(app, kAXMenuBarAttribute) else { return [] }
        var result: [MenuCommand] = []
        // Skip the first menu: it's the Apple menu.
        for top in menuItems(under: bar).dropFirst() {
            guard let title = string(top, kAXTitleAttribute), !title.isEmpty else { continue }
            walk(top, path: [title], depth: 1, maxDepth: maxDepth, into: &result)
        }
        return result
    }

    /// Clicks the item at `path`. Returns false if any title along the way wasn't found.
    @discardableResult
    static func press(path: [String], pid: pid_t) -> Bool {
        guard !path.isEmpty else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 2)
        guard var current = element(app, kAXMenuBarAttribute) else { return false }
        for title in path {
            guard let next = menuItems(under: current).first(where: {
                MenuPath.matches(string($0, kAXTitleAttribute) ?? "", title)
            }) else { return false }
            current = next
        }
        return AXUIElementPerformAction(current, kAXPressAction as CFString) == .success
    }

    // MARK: - Walking

    private static func walk(_ item: AXUIElement, path: [String], depth: Int, maxDepth: Int,
                             into result: inout [MenuCommand]) {
        for child in menuItems(under: item) {
            guard let title = string(child, kAXTitleAttribute), !title.isEmpty else { continue } // separators
            let childPath = path + [title]
            if hasSubmenu(child) {
                if depth < maxDepth, !skippedSubmenus.contains(MenuPath.normalize(title)) {
                    walk(child, path: childPath, depth: depth + 1, maxDepth: maxDepth, into: &result)
                }
                continue
            }
            result.append(MenuCommand(path: childPath, shortcut: shortcut(child),
                                      enabled: bool(child, kAXEnabledAttribute) ?? true))
        }
    }

    /// Menu bar → its items; a menu bar item or menu item → the items of its (single) submenu.
    private static func menuItems(under element: AXUIElement) -> [AXUIElement] {
        let kids = children(element)
        if kids.count == 1, string(kids[0], kAXRoleAttribute) == kAXMenuRole { return children(kids[0]) }
        return kids
    }

    private static func hasSubmenu(_ item: AXUIElement) -> Bool {
        children(item).contains { string($0, kAXRoleAttribute) == kAXMenuRole }
    }

    // MARK: - Shortcuts

    private static func shortcut(_ item: AXUIElement) -> String? {
        var key = string(item, kAXMenuItemCmdCharAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if key.isEmpty, let code = int(item, kAXMenuItemCmdVirtualKeyAttribute),
           let name = KeyNames.name(forKeyCode: UInt16(code)) {
            key = KeyCombo(key: name, modifiers: []).display
        }
        guard !key.isEmpty, let mods = int(item, kAXMenuItemCmdModifiersAttribute) else { return nil }
        // AX modifier bits: 1 = shift, 2 = option, 4 = control, 8 = *no* command.
        var s = ""
        if mods & 4 != 0 { s += "⌃" }
        if mods & 2 != 0 { s += "⌥" }
        if mods & 1 != 0 { s += "⇧" }
        if mods & 8 == 0 { s += "⌘" }
        return s + key.uppercased()
    }

    // MARK: - AX attribute helpers

    private static func value(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    private static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = value(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        (value(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func string(_ el: AXUIElement, _ name: String) -> String? { value(el, name) as? String }
    private static func int(_ el: AXUIElement, _ name: String) -> Int? { value(el, name) as? Int }
    private static func bool(_ el: AXUIElement, _ name: String) -> Bool? { value(el, name) as? Bool }
}
