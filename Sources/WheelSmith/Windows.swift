import AppKit
import ApplicationServices
import os

let windowLog = Logger(subsystem: "dev.wheelsmith.app", category: "windows")

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
    let pid: pid_t
    /// Window-server id, 0 when unknown.
    let windowID: CGWindowID
    let title: String
    /// Cocoa coordinates.
    let frame: CGRect
    let isMinimized: Bool
    let isFullScreen: Bool
    /// False for windows on another Space (other desktops, full-screen windows you're not looking at).
    let onCurrentSpace: Bool
    /// Index into the DisplayLayout it was listed with.
    let displayIndex: Int?
    /// The app's main window: the one a Dock click would bring forward.
    var isMain = false
}

/// Lists, raises and moves other apps' windows. Every call is synchronous IPC with the target app,
/// so call these off the main thread.
enum Windows {
    /// Standard windows of a running app: the current Space's front-most first, then those on other
    /// Spaces (including full-screen windows). Empty without Accessibility permission.
    static func list(bundleId: String, layout: DisplayLayout, timeout: Float = 0.25) -> [WindowInfo] {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
        else { return [] }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, timeout)
        let fallbackTitle = app.localizedName ?? "Window"

        // kAXWindows only covers the Spaces currently on screen.
        let visible = (value(appElement, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        let visibleIDs = Set(visible.map(windowID(of:)).filter { $0 != 0 })
        let main = value(appElement, kAXMainWindowAttribute).map { $0 as! AXUIElement }
        let result = visible.compactMap { w -> WindowInfo? in
            var window = info(w, pid: pid, onCurrentSpace: true, fallbackTitle: fallbackTitle, layout: layout)
            window?.isMain = main.map { CFEqual($0, w) } ?? false
            return window
        }
        // Remember them: the elements stay valid once you move to another Space.
        OtherSpaces.remember(pid: pid, result.compactMap { $0.windowID == 0 ? nil : ($0.windowID, $0.element) })
        let otherInfos = OtherSpaces.elements(pid: pid, excluding: visibleIDs).compactMap {
            info($0, pid: pid, onCurrentSpace: false, fallbackTitle: fallbackTitle, layout: layout)
        }
        windowLog.debug("\(bundleId, privacy: .public): \(result.count) on screen, \(otherInfos.count) on other Spaces")
        return result + otherInfos
    }

    private static let watchQueue = DispatchQueue(label: "dev.wheelsmith.windows.watch", qos: .utility)
    nonisolated(unsafe) private static var watched: [String] = []
    nonisolated(unsafe) private static var observers: [NSObjectProtocol] = []

    /// Keeps the window cache warm for these apps: lists their windows now, and again whenever you switch
    /// Space or app, so windows you've visited are known when they're later off screen. Main thread.
    static func watch(bundleIds: [String]) {
        watched = bundleIds
        if observers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { refreshWatched() }
                })
            }
        }
        MainActor.assumeIsolated { refreshWatched() }
    }

    @MainActor private static func refreshWatched() {
        guard AXIsProcessTrusted() else { return }
        let layout = DisplayLayout.current()
        let ids = watched
        // Wait for the Space switch to settle so its windows are reported as on screen.
        watchQueue.asyncAfter(deadline: .now() + 0.3) {
            for id in ids { _ = list(bundleId: id, layout: layout) }
        }
    }

    /// Brings the window to the front. For a window on another Space this also switches to that Space
    /// and activates the app, and returns true; otherwise the caller still activates the app.
    @discardableResult
    static func raise(_ window: WindowInfo) -> Bool {
        if window.isMinimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        var handled = false
        if !window.onCurrentSpace, window.windowID != 0 {
            handled = PrivateAPI.makeFront(pid: window.pid, windowID: window.windowID)
        }
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        return handled
    }

    /// Moves the window onto display `index`, centered, shrunk if needed to fit its visible area.
    /// A full-screen window leaves full screen, moves, and goes full screen again on that display.
    /// Blocks while a full-screen window animates, so call off the main thread.
    static func move(_ window: WindowInfo, toDisplay index: Int, layout: DisplayLayout) {
        guard window.displayIndex != index, layout.visibleFrames.indices.contains(index) else { return }
        if window.isFullScreen {
            moveFullScreen(window, toDisplay: index, layout: layout)
        } else {
            place(window.element, size: window.frame.size, onDisplay: index, layout: layout)
        }
    }

    private static func place(_ element: AXUIElement, size: CGSize, onDisplay index: Int, layout: DisplayLayout) {
        let area = layout.visibleFrames[index]
        var size = CGSize(width: min(size.width, area.width), height: min(size.height, area.height))
        // AX positions use a top-left origin on the primary display.
        var topLeft = CGPoint(x: area.midX - size.width / 2, y: layout.primaryMaxY - (area.midY + size.height / 2))
        setPoint(element, kAXPositionAttribute, &topLeft)
        if let sz = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sz)
        }
        // Some apps clamp the size while still on the old display; set the position once more.
        setPoint(element, kAXPositionAttribute, &topLeft)
    }

    /// A full-screen window is its own Space and can't be positioned, so: exit full screen, wait for
    /// the animation to finish, move it, and enter full screen again (now on the target display).
    private static func moveFullScreen(_ window: WindowInfo, toDisplay index: Int, layout: DisplayLayout) {
        let el = window.element
        AXUIElementSetMessagingTimeout(el, 1)
        // Its Space has to be on screen for the window to leave full screen.
        if !window.onCurrentSpace, window.windowID != 0, PrivateAPI.makeFront(pid: window.pid, windowID: window.windowID) {
            Thread.sleep(forTimeInterval: 0.5)
        }
        AXUIElementSetAttributeValue(el, "AXFullScreen" as CFString, kCFBooleanFalse)
        // The attribute flips before the animation ends; wait until the frame has stopped changing too.
        var last: CGRect?
        var stable = 0
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, stable < 3 {
            Thread.sleep(forTimeInterval: 0.1)
            let current = frame(of: el, layout: layout)
            let windowed = (value(el, "AXFullScreen") as? Bool) == false
            stable = windowed && current != nil && current == last ? stable + 1 : 0
            last = current
        }
        guard stable >= 3, let windowed = last else {
            windowLog.debug("full-screen window didn't leave full screen in time; not moved")
            return
        }
        place(el, size: windowed.size, onDisplay: index, layout: layout)
        Thread.sleep(forTimeInterval: 0.15)
        AXUIElementSetAttributeValue(el, "AXFullScreen" as CFString, kCFBooleanTrue)
        // Let it settle into its new Space before the caller raises it.
        Thread.sleep(forTimeInterval: 0.8)
    }

    // MARK: - Helpers

    private static func info(_ w: AXUIElement, pid: pid_t, onCurrentSpace: Bool, fallbackTitle: String,
                             layout: DisplayLayout) -> WindowInfo? {
        AXUIElementSetMessagingTimeout(w, 0.25)
        // Skip panels, sheets, palettes, tooltips…
        guard (value(w, kAXRoleAttribute) as? String) == kAXWindowRole,
              (value(w, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole,
              let frame = frame(of: w, layout: layout) else { return nil }
        let title = (value(w, kAXTitleAttribute) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return WindowInfo(element: w, pid: pid, windowID: windowID(of: w),
                          title: title.isEmpty ? fallbackTitle : title,
                          frame: frame,
                          isMinimized: (value(w, kAXMinimizedAttribute) as? Bool) ?? false,
                          isFullScreen: (value(w, "AXFullScreen") as? Bool) ?? false,
                          onCurrentSpace: onCurrentSpace,
                          displayIndex: layout.index(containing: frame))
    }

    static func windowID(of element: AXUIElement) -> CGWindowID {
        guard let getWindow = PrivateAPI.getWindow else { return 0 }
        var id: CGWindowID = 0
        return getWindow(element, &id) == .success ? id : 0
    }

    fileprivate static func setPoint(_ el: AXUIElement, _ name: String, _ point: inout CGPoint) {
        if let v = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(el, name as CFString, v) }
    }

    fileprivate static func value(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
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

// MARK: - Windows on other Spaces

/// macOS's Accessibility API only lists an app's windows on the Spaces currently on screen. Windows on
/// other desktops, and full-screen windows (each is its own Space), are missing.
///
/// The window server does know about them (without titles), so we compare its list with the AX list,
/// and for any window missing from AX we look up its AX element by trying the app's element ids, the
/// way window switchers such as AltTab do. Results are cached per window, so the scan only runs when
/// a new window appears.
private enum OtherSpaces {
    private static let lock = NSLock()
    /// pid → window id → AX element of a standard window.
    nonisolated(unsafe) private static var found: [pid_t: [CGWindowID: AXUIElement]] = [:]
    /// pid → window ids we scanned for without finding a standard window, and until when to skip them.
    /// A complete scan rules a window out for good; one cut short by the time budget, for a minute.
    nonisolated(unsafe) private static var ignored: [pid_t: [CGWindowID: Date]] = [:]

    static func remember(pid: pid_t, _ windows: [(CGWindowID, AXUIElement)]) {
        guard !windows.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        for (id, element) in windows {
            found[pid, default: [:]][id] = element
            ignored[pid]?[id] = nil
        }
    }

    static func elements(pid: pid_t, excluding visible: Set<CGWindowID>) -> [AXUIElement] {
        guard PrivateAPI.createWithToken != nil, PrivateAPI.getWindow != nil else { return [] }
        let serverIDs = windowServerIDs(pid: pid)
        let alive = Set(serverIDs)

        lock.lock()
        found[pid] = found[pid]?.filter { alive.contains($0.key) }
        let now = Date()
        ignored[pid] = ignored[pid]?.filter { alive.contains($0.key) && $0.value > now }
        let known = Set(found[pid].map { Array($0.keys) } ?? []).union(ignored[pid]?.keys ?? [:].keys)
        lock.unlock()

        let unknown = alive.subtracting(visible).subtracting(known)
        if !unknown.isEmpty {
            let (hits, complete) = scan(pid: pid, for: unknown)
            lock.lock()
            found[pid, default: [:]].merge(hits) { _, new in new }
            let until = complete ? Date.distantFuture : Date().addingTimeInterval(300)
            for id in unknown where hits[id] == nil { ignored[pid, default: [:]][id] = until }
            lock.unlock()
        }

        lock.lock(); defer { lock.unlock() }
        let cache = found[pid] ?? [:]
        return serverIDs.filter { !visible.contains($0) }.compactMap { cache[$0] }
    }

    /// The app's normal-level windows across all Spaces, front-most first. No permission needed.
    private static func windowServerIDs(pid: pid_t) -> [CGWindowID] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return list.compactMap { w in
            guard (w[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let number = w[kCGWindowNumber as String] as? Int,
                  let bounds = w[kCGWindowBounds as String].flatMap({ CGRect(dictionaryRepresentation: $0 as! CFDictionary) }),
                  bounds.width >= 100, bounds.height >= 100 // skip helper strips, e.g. full-screen title bars
            else { return nil }
            return CGWindowID(number)
        }
    }

    /// Tries the app's AX element ids until every wanted window is found or the time budget runs out.
    private static func scan(pid: pid_t, for wanted: Set<CGWindowID>,
                             budget: TimeInterval = 0.4) -> (found: [CGWindowID: AXUIElement], complete: Bool) {
        guard let create = PrivateAPI.createWithToken, let getWindow = PrivateAPI.getWindow else { return ([:], false) }
        // Remote token layout: pid, 0, "coco", element id.
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { p in
            p.storeBytes(of: pid, toByteOffset: 0, as: Int32.self)
            p.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
            p.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self)
        }
        let start = Date()
        let deadline = start.addingTimeInterval(budget)
        var hits: [CGWindowID: AXUIElement] = [:]
        func report(_ last: UInt64, _ complete: Bool) {
            windowLog.debug("scan pid \(pid): found \(hits.count)/\(wanted.count) up to element \(last), complete=\(complete), \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        }
        for elementID: UInt64 in 0..<20_000 {
            if hits.count == wanted.count { report(elementID, true); return (hits, true) }
            if elementID % 64 == 0, Date() > deadline { report(elementID, false); return (hits, false) }
            token.withUnsafeMutableBytes { $0.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self) }
            guard let element = create(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(element, 0.05)
            var id: CGWindowID = 0
            // Any element inside a window reports that window's id; keep only the window itself.
            if getWindow(element, &id) == .success, wanted.contains(id), hits[id] == nil,
               (Windows.value(element, kAXRoleAttribute) as? String) == kAXWindowRole {
                hits[id] = element
            }
        }
        report(20_000, true)
        return (hits, true)
    }
}

// MARK: - Private macOS calls

/// Undocumented calls used by window switchers (AltTab and others) for years. Looked up at runtime, so if
/// a future macOS drops them the wheel simply stops listing windows on other Spaces.
enum PrivateAPI {
    typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    typealias CreateWithTokenFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    typealias SetFrontProcessFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    typealias PostEventRecordFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        _ = skyLight
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil } // RTLD_DEFAULT
        return unsafeBitCast(sym, to: type)
    }

    static let getWindow = symbol("_AXUIElementGetWindow", GetWindowFn.self)
    static let createWithToken = symbol("_AXUIElementCreateWithRemoteToken", CreateWithTokenFn.self)
    private static let setFrontProcess = symbol("_SLPSSetFrontProcessWithOptions", SetFrontProcessFn.self)
    private static let postEventRecord = symbol("SLPSPostEventRecordTo", PostEventRecordFn.self)
    private static let getProcessForPID = symbol("GetProcessForPID", GetProcessForPIDFn.self)

    /// Activates the app with this exact window in front, switching to its Space if needed.
    static func makeFront(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let setFrontProcess, let postEventRecord, let getProcessForPID else { return false }
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == noErr else { return false }
        let userGenerated: UInt32 = 0x200
        guard setFrontProcess(&psn, windowID, userGenerated) == .success else { return false }
        // Make it the key window: two synthetic window-server events.
        for kind: UInt8 in [0x01, 0x02] {
            var bytes = [UInt8](repeating: 0, count: 0xF8)
            bytes[0x04] = 0xF8
            bytes[0x08] = kind
            bytes[0x3A] = 0x10
            withUnsafeBytes(of: windowID) { for (i, b) in $0.enumerated() { bytes[0x3C + i] = b } }
            for i in 0x20..<0x30 { bytes[i] = 0xFF }
            _ = bytes.withUnsafeMutableBufferPointer { postEventRecord(&psn, $0.baseAddress!) }
        }
        return true
    }
}
