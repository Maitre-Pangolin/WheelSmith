import AppKit
import ApplicationServices

/// A snapshot of the display arrangement, taken on the main thread so window work can run elsewhere.
struct DisplayLayout {
    /// Cocoa coordinates (origin bottom-left of the primary display), in NSScreen.screens order.
    let frames: [CGRect]
    let visibleFrames: [CGRect]
    let primaryMaxY: CGFloat

    /// Call on the main thread.
    static func current() -> DisplayLayout {
        let screens = NSScreen.screens
        return DisplayLayout(frames: screens.map(\.frame), visibleFrames: screens.map(\.visibleFrame),
                             primaryMaxY: screens.first?.frame.maxY ?? 0)
    }

    var count: Int { frames.count }

    /// Index of the display a rect is mostly on.
    func index(containing rect: CGRect) -> Int? {
        let areas = frames.map { f -> CGFloat in
            let i = f.intersection(rect)
            return i.isNull ? 0 : i.width * i.height
        }
        guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 else { return nil }
        return best
    }

    func index(containing point: CGPoint) -> Int? {
        frames.firstIndex { NSMouseInRect(point, $0, false) }
    }
}

/// One window of another app, as seen through the Accessibility API.
struct WindowInfo: Identifiable {
    let id = UUID()
    let element: AXUIElement
    let title: String
    /// Cocoa coordinates.
    let frame: CGRect
    let isMinimized: Bool
    let isFullScreen: Bool
    /// Index into the DisplayLayout it was listed with.
    let displayIndex: Int?
}

/// Lists, raises and moves other apps' windows. Every call is synchronous IPC with the target app,
/// so call these off the main thread.
enum Windows {
    /// Standard windows of a running app, front-most first. Empty without Accessibility permission.
    static func list(bundleId: String, layout: DisplayLayout, timeout: Float = 0.25) -> [WindowInfo] {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
        else { return [] }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, timeout)
        let fallbackTitle = app.localizedName ?? "Window"
        let windows = (value(appElement, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return windows.compactMap { w in
            // Skip panels, sheets, palettes, tooltips…
            guard (value(w, kAXRoleAttribute) as? String) == kAXWindowRole,
                  (value(w, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole,
                  let frame = frame(of: w, layout: layout) else { return nil }
            let title = (value(w, kAXTitleAttribute) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            return WindowInfo(element: w,
                              title: title.isEmpty ? fallbackTitle : title,
                              frame: frame,
                              isMinimized: (value(w, kAXMinimizedAttribute) as? Bool) ?? false,
                              isFullScreen: (value(w, "AXFullScreen") as? Bool) ?? false,
                              displayIndex: layout.index(containing: frame))
        }
    }

    /// Un-minimizes the window and makes it the app's front window. The caller then activates the app.
    static func raise(_ window: WindowInfo) {
        if window.isMinimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }

    /// Moves the window onto display `index`, centered, shrunk if needed to fit its visible area.
    /// Full-screen windows can't be moved and are left alone.
    static func move(_ window: WindowInfo, toDisplay index: Int, layout: DisplayLayout) {
        guard !window.isFullScreen, window.displayIndex != index, layout.visibleFrames.indices.contains(index) else { return }
        let area = layout.visibleFrames[index]
        var size = CGSize(width: min(window.frame.width, area.width), height: min(window.frame.height, area.height))
        // AX positions use a top-left origin on the primary display.
        var topLeft = CGPoint(x: area.midX - size.width / 2, y: layout.primaryMaxY - (area.midY + size.height / 2))
        setPoint(window.element, kAXPositionAttribute, &topLeft)
        if let sz = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sz)
        }
        // Some apps clamp the size while still on the old display; set the position once more.
        setPoint(window.element, kAXPositionAttribute, &topLeft)
    }

    // MARK: - Helpers

    private static func setPoint(_ el: AXUIElement, _ name: String, _ point: inout CGPoint) {
        if let v = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(el, name as CFString, v) }
    }

    private static func value(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    private static func frame(of w: AXUIElement, layout: DisplayLayout) -> CGRect? {
        guard let posValue = value(w, kAXPositionAttribute), let sizeValue = value(w, kAXSizeAttribute),
              CFGetTypeID(posValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(x: pos.x, y: layout.primaryMaxY - pos.y - size.height, width: size.width, height: size.height)
    }
}
