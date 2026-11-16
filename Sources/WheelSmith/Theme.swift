import SwiftUI
import AppKit
import RingCore

/// A theme as the wheel draws it: built from a `ThemeSpec` in the catalog (`design/themes/themes.json`).
///
/// The wheel draws from `spec` (gradients, edges, glows, fonts). The flattened colors below are for
/// simpler surfaces, like the prompt's text field card.
struct Theme: Identifiable {
    let spec: ThemeSpec
    /// Blur material behind the disk.
    let material: NSVisualEffectView.Material
    /// Tint laid over the backdrop.
    let disk: Color
    /// The disk's (and hub's) outline.
    let stroke: Color
    /// A slice wedge at rest.
    let slice: Color
    /// The hovered slice's wedge (a quiet fill: the rails carry the selection).
    let sliceHover: Color
    /// Selection rails and the Settings arm ring.
    let rail: Color
    let hub: Color
    /// Hub fill while letting go there would open Settings.
    let hubHover: Color
    let text: Color
    let subtext: Color
    /// A sub-action wedge at rest.
    let sub: Color
    /// The hovered sub-action: a 2-stop gradient (top-leading → bottom-trailing).
    let subHover: [Color]
    let symbol: Color
    /// Labels and symbols drawn on top of `subHover`.
    let onHover: Color
    let shadow: Color

    var id: String { spec.id }
    var name: String { spec.name }
    var isDark: Bool { spec.isDark }

    init(_ spec: ThemeSpec) {
        self.spec = spec
        material = spec.isDark ? .hudWindow : .popover
        disk = Self.flat(spec.disk)
        stroke = Color(spec.diskEdge.border?.color ?? .clear)
        slice = Self.flat(spec.slice)
        sliceHover = Self.flat(spec.sliceHover)
        rail = Color(spec.rail.colors.first ?? .white)
        hub = Self.flat(spec.hub)
        hubHover = Self.flat(spec.hubHover)
        text = Color(spec.text)
        subtext = Color(spec.subtext)
        sub = Self.flat(spec.sub)
        let hover = spec.subHover.baseColors.map(Color.init)
        subHover = hover.count >= 2 ? [hover[0], hover[hover.count - 1]] : [hover.first ?? .white, hover.first ?? .white]
        symbol = Color(spec.symbol)
        onHover = Color(spec.onHover)
        let drop = spec.diskEdge.shadows?.filter { $0.inset != true }.max { $0.blur < $1.blur }
        shadow = Color(drop?.color ?? .clear)
    }

    /// One color for a paint: itself when solid, else the average of its bottom layer's stops.
    private static func flat(_ paint: Paint) -> Color {
        let colors = paint.baseColors
        guard !colors.isEmpty else { return .clear }
        let n = Double(colors.count)
        return Color(RGBA(colors.map(\.r).reduce(0, +) / n, colors.map(\.g).reduce(0, +) / n,
                          colors.map(\.b).reduce(0, +) / n, colors.map(\.a).reduce(0, +) / n))
    }

    /// Every built-in theme.
    static let catalog: [Theme] = ThemeCatalog.builtIn.map(Theme.init)

    /// The original themes, from before the designed set.
    static let originalIDs: Set = ["midnight", "daylight"]

    /// Themes as Settings offers them: designed light, designed dark, then the originals.
    static let groups: [(title: String, themes: [Theme])] = [
        ("Light themes", catalog.filter { !$0.isDark && !originalIDs.contains($0.id) }),
        ("Dark themes", catalog.filter { $0.isDark && !originalIDs.contains($0.id) }),
        ("Original themes", catalog.filter { originalIDs.contains($0.id) }),
    ]

    static let midnight = named("midnight")

    static func named(_ id: String) -> Theme {
        let id = ThemeCatalog.resolve(id)
        return catalog.first { $0.id == id } ?? catalog[0]
    }
}

extension Color {
    init(_ c: RGBA) {
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }
}
