import Foundation

/// Helpers for menu-bar paths like ["Shell", "New Tab"].
public enum MenuPath {
    /// Titles compare loosely: case, surrounding spaces and a trailing "…" / "..." are ignored,
    /// so "New Window…" in the config still matches after an app drops the ellipsis.
    public static func normalize(_ title: String) -> String {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["…", "..."] where t.hasSuffix(suffix) {
            t = String(t.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    public static func matches(_ a: String, _ b: String) -> Bool {
        normalize(a) == normalize(b)
    }

    /// "Shell › New Tab"
    public static func display(_ path: [String]) -> String {
        path.joined(separator: " › ")
    }

    /// A short label for a wheel slice: the last title, without its ellipsis.
    public static func label(for path: [String]) -> String {
        guard var t = path.last?.trimmingCharacters(in: .whitespaces) else { return "" }
        for suffix in ["…", "..."] where t.hasSuffix(suffix) { t = String(t.dropLast(suffix.count)) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Does `query` match this command? Every word must appear in the path or the shortcut.
    public static func search(_ query: String, path: [String], shortcut: String?) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = (path + [shortcut ?? ""]).joined(separator: " ").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }

    /// Best-effort SF Symbol for a menu command, so added sub-actions don't all look the same.
    public static func symbol(for path: [String]) -> String {
        let title = normalize(path.last ?? "")
        let rules: [(keywords: [String], symbol: String)] = [
            (["new tab"], "plus.square.on.square"),
            (["new window", "new private window", "new incognito"], "macwindow.badge.plus"),
            (["new message", "new email", "new mail", "compose"], "square.and.pencil"),
            (["new note"], "note.text.badge.plus"),
            (["new chat", "new conversation"], "plus.bubble"),
            (["new folder"], "folder.badge.plus"),
            (["new file"], "doc.badge.plus"),
            (["split"], "rectangle.split.2x1"),
            (["find", "search", "jump to", "quick open", "go to"], "magnifyingglass"),
            (["reload", "refresh"], "arrow.clockwise"),
            (["close"], "xmark"),
            (["settings", "preferences"], "gearshape"),
            (["calendar"], "calendar"),
            (["inbox", "mail"], "tray"),
            (["history", "recent"], "clock.arrow.circlepath"),
            (["bookmark"], "bookmark"),
            (["download"], "arrow.down.circle"),
            (["print"], "printer"),
            (["save"], "square.and.arrow.down"),
            (["share", "export"], "square.and.arrow.up"),
            (["sidebar"], "sidebar.left"),
            (["terminal", "shell"], "terminal"),
            (["zoom in"], "plus.magnifyingglass"),
            (["zoom out"], "minus.magnifyingglass"),
            (["full screen", "fullscreen"], "arrow.up.left.and.arrow.down.right"),
            (["minimize"], "minus.square"),
            (["thread"], "bubble.left.and.bubble.right"),
            (["mention", "activity"], "at"),
            (["copy"], "doc.on.doc"),
            (["paste"], "doc.on.clipboard"),
            (["undo"], "arrow.uturn.backward"),
            (["new"], "plus"),
            (["open"], "arrow.up.forward.app"),
        ]
        for rule in rules where rule.keywords.contains(where: title.contains) {
            return rule.symbol
        }
        return "filemenu.and.selection"
    }
}
