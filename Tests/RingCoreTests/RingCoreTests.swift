// Note: deliberately no `import Foundation` — the Command Line Tools ship swift-testing without its
// Foundation cross-import overlay, so importing both fails to build. Darwin is enough here.
import Darwin
import Testing
@testable import RingCore

// MARK: - Geometry

private func point(angleDegrees: Double, radius: Double) -> (Double, Double) {
    let a = angleDegrees * .pi / 180
    return (radius * sin(a), radius * cos(a)) // dy up
}

@Suite struct GeometryTests {
    let m = WheelMetrics.standard
    let geo = WheelGeometry(childCounts: [2, 0, 3, 0, 0, 0, 0, 1])

    @Test func centerIsHub() {
        #expect(geo.hit(dx: 0, dy: 0, openParent: nil) == .center)
        #expect(geo.hit(dx: 10, dy: -20, openParent: nil) == .center)
    }

    @Test func eightSlicesClockwiseFromTop() {
        for i in 0..<8 {
            let (dx, dy) = point(angleDegrees: Double(i) * 45, radius: 100)
            #expect(geo.hit(dx: dx, dy: dy, openParent: nil) == .item(i))
        }
        // Just either side of the top slice's edges.
        let (lx, ly) = point(angleDegrees: -22, radius: 100)
        #expect(geo.hit(dx: lx, dy: ly, openParent: nil) == .item(0))
        let (rx, ry) = point(angleDegrees: 23, radius: 100)
        #expect(geo.hit(dx: rx, dy: ry, openParent: nil) == .item(1))
    }

    @Test func tenSlicesClockwiseFromTop() {
        let ten = WheelGeometry(childCounts: Array(repeating: 0, count: 10))
        for i in 0..<10 {
            let (dx, dy) = point(angleDegrees: Double(i) * 36, radius: 100)
            #expect(ten.hit(dx: dx, dy: dy, openParent: nil) == .item(i))
        }
    }

    @Test func farOutsideCancels() {
        let (dx, dy) = point(angleDegrees: 45, radius: m.ringOuter + m.cancelSlack + 5)
        #expect(geo.hit(dx: dx, dy: dy, openParent: nil) == .cancel)
    }

    @Test func slackBandStillSelectsSlice() {
        let (dx, dy) = point(angleDegrees: 90, radius: m.ringOuter + 10)
        #expect(geo.hit(dx: dx, dy: dy, openParent: nil) == .item(2))
    }

    @Test func childAnglesFanAroundParent() {
        let angles = geo.childAngles(parent: 2) // 3 children around 90°
        #expect(angles.count == 3)
        #expect(abs(angles[1] - .pi / 2) < 1e-9)
        #expect(abs(angles[0] - (.pi / 2 - m.childSpan)) < 1e-9)
        // Top slice children wrap around 0.
        let top = geo.childAngles(parent: 0)
        #expect(top.allSatisfy { $0 >= 0 && $0 < 2 * .pi })
    }

    @Test func childrenOnlyWhenParentOpen() {
        let (dx, dy) = point(angleDegrees: 90 + 34, radius: 200)
        #expect(geo.hit(dx: dx, dy: dy, openParent: 2) == .child(2, 2))
        #expect(geo.hit(dx: dx, dy: dy, openParent: nil) == .cancel)
    }

    @Test func trackerKeepsParentWhileSlidingAlongSubRing() {
        var t = WheelTracker(geometry: geo)
        // Go out through slice 2 (90°)...
        t.update(dx: 0, dy: 0)
        var (dx, dy) = point(angleDegrees: 90, radius: 100)
        #expect(t.update(dx: dx, dy: dy) == .item(2))
        #expect(t.openParent == 2)
        (dx, dy) = point(angleDegrees: 90, radius: 200)
        #expect(t.update(dx: dx, dy: dy) == .child(2, 1))
        // ...then slide sideways along the sub ring, past where slice 3 begins (112.5°).
        (dx, dy) = point(angleDegrees: 122, radius: 200)
        #expect(t.update(dx: dx, dy: dy) == .child(2, 2))
        #expect(t.openParent == 2)
        // Back to the center closes it.
        t.update(dx: 0, dy: 0)
        #expect(t.openParent == nil)
    }

    @Test func sliceWithoutChildrenOpensNothing() {
        var t = WheelTracker(geometry: geo)
        let (dx, dy) = point(angleDegrees: 135, radius: 100)
        #expect(t.update(dx: dx, dy: dy) == .item(3))
        #expect(t.openParent == nil)
    }

    @Test func emptyWheel() {
        let g = WheelGeometry(childCounts: [])
        #expect(g.hit(dx: 0, dy: 0, openParent: nil) == .center)
        #expect(g.hit(dx: 100, dy: 0, openParent: nil) == .cancel)
    }
}

// MARK: - Key combos

@Suite struct KeyComboTests {
    @Test func parsesAndCanonicalizes() throws {
        let c = try #require(KeyCombo("Shift+CMD+n"))
        #expect(c.key == "n")
        #expect(c.modifiers == [.shift, .cmd])
        #expect(c.string == "shift+cmd+n")
        #expect(c.display == "⇧⌘N")
    }

    @Test func namedKeysAndAliases() throws {
        #expect(try #require(KeyCombo("option+space")).display == "⌥ Space")
        #expect(try #require(KeyCombo("alt+esc")).key == "escape")
        #expect(try #require(KeyCombo("cmd++")).key == "+")
        #expect(try #require(KeyCombo("f13")).modifiers.isEmpty)
    }

    @Test func rejectsGarbage() {
        #expect(KeyCombo("") == nil)
        #expect(KeyCombo("hyper+n") == nil)
        #expect(KeyCombo("cmd+banana") == nil)
        #expect(KeyCombo("cmd+") == nil)
    }
}

// MARK: - Config

@Suite struct ConfigTests {
    @Test func defaultConfigRoundTrips() throws {
        let config = DefaultConfig.config
        #expect(config.items.count == RingConfig.maxItems)
        let decoded = try ConfigFile.decode(ConfigFile.encode(config))
        #expect(decoded.sameContent(as: config))
        #expect(decoded.items[0].children.count == 2)
    }

    @Test func handWrittenJSON() throws {
        let json = """
        { "items": [
            { "label": "Term", "action": { "type": "app", "bundleId": "com.googlecode.iterm2" } },
            { "label": "Docs", "icon": "sf:book", "action": { "type": "url", "url": "https://example.com" } },
            { "label": "Group", "children": [ { "label": "Echo", "action": { "type": "shell", "command": "echo hi" } } ] }
        ] }
        """
        let c = try ConfigFile.decode(json: json)
        #expect(c.hotkey == "option+space")
        #expect(c.theme == "midnight")
        #expect(c.items[0].action == .app(bundleId: "com.googlecode.iterm2"))
        #expect(c.items[1].action == .url("https://example.com", bundleId: nil))
        #expect(c.items[2].action == .none)
        #expect(c.items[2].children[0].action == .shell("echo hi"))
    }

    @Test func clampsItemCounts() throws {
        let child = WheelItem(label: "c", action: .none)
        let item = WheelItem(label: "x", action: .none, children: Array(repeating: child, count: 9))
        let big = RingConfig(items: Array(repeating: item, count: 12))
        let c = try ConfigFile.decode(ConfigFile.encode(big))
        #expect(c.items.count == RingConfig.maxItems)
        #expect(c.items[0].children.count == RingConfig.maxChildren)
    }

    @Test func convertingActionKeepsApp() {
        let a = Action.app(bundleId: "x.y")
        #expect(a.converted(to: .keys) == .keys("", bundleId: "x.y"))
        #expect(Action.keys("cmd+t", bundleId: "x.y").converted(to: .app) == .app(bundleId: "x.y"))
    }
}

// MARK: - Menu actions

@Suite struct MenuActionTests {
    @Test func menuActionRoundTrips() throws {
        let json = """
        { "items": [ { "label": "iTerm", "action": { "type": "app", "bundleId": "com.googlecode.iterm2" },
          "children": [ { "label": "New Tab", "action": { "type": "menu", "menu": ["Shell", "New Tab"], "bundleId": "com.googlecode.iterm2" } } ] } ] }
        """
        let c = try ConfigFile.decode(json: json)
        let action = c.items[0].children[0].action
        #expect(action == .menu(["Shell", "New Tab"], bundleId: "com.googlecode.iterm2"))
        #expect(action.kind == .menu)
        #expect(action.bundleId == "com.googlecode.iterm2")
        #expect(try ConfigFile.decode(ConfigFile.encode(c)).sameContent(as: c))
    }

    @Test func convertingToMenuKeepsApp() {
        #expect(Action.keys("cmd+t", bundleId: "x.y").converted(to: .menu) == .menu([], bundleId: "x.y"))
        #expect(Action.menu(["File", "New"], bundleId: "x.y").converted(to: .app) == .app(bundleId: "x.y"))
    }

    @Test func titlesMatchLoosely() {
        #expect(MenuPath.matches("New Window…", "new window"))
        #expect(MenuPath.matches("Open Recent...", "Open  Recent"))
        #expect(!MenuPath.matches("New Tab", "New Window"))
    }

    @Test func labelsAndDisplay() {
        #expect(MenuPath.label(for: ["File", "New Window…"]) == "New Window")
        #expect(MenuPath.display(["Shell", "Split", "Vertically"]) == "Shell › Split › Vertically")
    }

    @Test func searchNeedsEveryWord() {
        #expect(MenuPath.search("new tab", path: ["Shell", "New Tab"], shortcut: "⌘T"))
        #expect(MenuPath.search("shell tab", path: ["Shell", "New Tab"], shortcut: nil))
        #expect(!MenuPath.search("window tab", path: ["Shell", "New Tab"], shortcut: nil))
        #expect(MenuPath.search("⌘t", path: ["Shell", "New Tab"], shortcut: "⌘T"))
        #expect(MenuPath.search("  ", path: ["x"], shortcut: nil))
    }

    @Test func symbolGuesses() {
        #expect(MenuPath.symbol(for: ["Shell", "New Tab"]) == "plus.square.on.square")
        #expect(MenuPath.symbol(for: ["File", "New Window…"]) == "macwindow.badge.plus")
        #expect(MenuPath.symbol(for: ["Edit", "Find", "Find…"]) == "magnifyingglass")
        #expect(MenuPath.symbol(for: ["Help", "Something Odd"]) == "filemenu.and.selection")
    }
}

// MARK: - Window ring

@Suite struct RingLayoutTests {
    @Test func windowsOnlyWhenMoreThanOne() {
        #expect(RingLayout.counts(windows: 0, actions: 2) == (0, 2))
        #expect(RingLayout.counts(windows: 1, actions: 2) == (0, 2))
        #expect(RingLayout.counts(windows: 2, actions: 2) == (2, 2))
    }

    @Test func capsKeepSomeActionsReachable() {
        #expect(RingLayout.counts(windows: 10, actions: 5) == (6, 2))
        #expect(RingLayout.counts(windows: 4, actions: 5) == (4, 4))
        #expect(RingLayout.counts(windows: 3, actions: 0) == (3, 0))
    }

    @Test func eightEntriesFitAroundAnySlice() {
        let geo = WheelGeometry(childCounts: [8, 0, 0, 0, 0, 0, 0, 0])
        let angles = geo.childAngles(parent: 0)
        #expect(angles.count == 8)
        // Every entry is still selectable by angle.
        for (j, a) in angles.enumerated() {
            let dx = 200 * sin(a), dy = 200 * cos(a)
            #expect(geo.hit(dx: dx, dy: dy, openParent: 0) == .child(0, j))
        }
    }

    @Test func bringHereRoundTripsAndDefaultsOff() throws {
        let c = try ConfigFile.decode(json: """
        { "items": [ { "label": "A", "action": { "type": "app", "bundleId": "a" }, "bringHere": true },
                     { "label": "B", "action": { "type": "app", "bundleId": "b" } } ] }
        """)
        #expect(c.items[0].bringHere)
        #expect(!c.items[1].bringHere)
        #expect(try ConfigFile.decode(ConfigFile.encode(c)).sameContent(as: c))
    }
}

// MARK: - Prompt actions

@Suite struct PromptActionTests {
    @Test func promptActionRoundTrips() throws {
        let json = #"""
        { "items": [ { "label": "Ostraka", "action": { "type": "app", "bundleId": "x.y" },
          "children": [ { "label": "Quick todo", "action": { "type": "prompt", "command": "ostraka todo add \"$1\"", "placeholder": "Title #tag" } } ] } ] }
        """#
        let c = try ConfigFile.decode(json: json)
        let action = c.items[0].children[0].action
        #expect(action == .prompt(command: #"ostraka todo add "$1""#, placeholder: "Title #tag"))
        #expect(action.kind == .prompt)
        #expect(action.bundleId == nil)
        #expect(try ConfigFile.decode(ConfigFile.encode(c)).sameContent(as: c))
    }

    @Test func placeholderIsOptional() throws {
        let json = #"{ "items": [ { "label": "Ask", "action": { "type": "prompt", "command": "say \"$1\"" } } ] }"#
        #expect(try ConfigFile.decode(json: json).items[0].action == .prompt(command: #"say "$1""#, placeholder: nil))
    }

    @Test func convertingBetweenShellAndPromptKeepsCommand() {
        #expect(Action.shell("echo").converted(to: .prompt) == .prompt(command: "echo", placeholder: nil))
        #expect(Action.prompt(command: "echo", placeholder: "x").converted(to: .shell) == .shell("echo"))
    }

    @Test func defaultOstrakaSliceHasQuickTodo() {
        let ostraka = DefaultConfig.config.items.first { $0.label == "Ostraka" }
        #expect(ostraka?.children.first?.action.kind == .prompt)
    }
}

// MARK: - Prompt placement

@Suite struct PromptPlacementTests {
    /// 4 slices: right (index 1) and left (index 3) at 3 and 9 o'clock.
    let geometry = WheelGeometry(childCounts: [0, 3, 0, 3])
    let m = WheelMetrics.standard

    @Test func clearsTheDiskWithoutOpenSubActions() {
        #expect(geometry.horizontalClearance(halfHeight: 60, openParent: nil) == m.ringOuter)
        #expect(geometry.horizontalClearance(halfHeight: 60, openParent: 0, side: 1) == m.ringOuter)
    }

    @Test func clearsSubActionsOnTheSameSide() {
        let right = geometry.horizontalClearance(halfHeight: 60, openParent: 1, side: 1)
        #expect(right > m.subOuter - 1 && right <= m.subOuter)
        // The right-hand sub-actions don't push a field on the left.
        #expect(geometry.horizontalClearance(halfHeight: 60, openParent: 1, side: -1) == m.ringOuter)
    }

    @Test func ignoresSubActionsAboveTheField() {
        // Slice 0 is at 12 o'clock: its sub-actions are well above a field centered on the wheel.
        let top = WheelGeometry(childCounts: [3, 0, 0, 0])
        #expect(top.horizontalClearance(halfHeight: 60, openParent: 0, side: 1) == m.ringOuter)
    }
}
