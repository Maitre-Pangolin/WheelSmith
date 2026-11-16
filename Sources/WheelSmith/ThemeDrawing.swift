import SwiftUI
import AppKit
import RingCore

// Draws the parts of a `ThemeSpec` that aren't a single color: layered gradients, edges (borders,
// drop and inset shadows, outline rings), rail strokes and theme fonts. Rules follow CSS, which the
// designs were made in:
// - a paint is laid out in a "box" (the design's element): 400 pt for the disk, 128 pt for the hub,
//   and the whole 720 pt wheel area for wedge and sub-action paints, clipped to the wedge;
// - layers stack top first; a tiled layer repeats every `tile` points from the box's corner;
// - outer shadows only show outside the shape, inset shadows only inside it.

// MARK: - Paint

/// A paint laid out in `box` and clipped to `clip` (both in this view's coordinates).
struct PaintView: View, Equatable {
    let paint: Paint
    let box: CGRect
    var clip: Path?

    var body: some View {
        if paint.layers.count == 1, case .solid(let c) = paint.layers[0] {
            (clip ?? Path(box)).fill(Color(c))
        } else {
            canvas
        }
    }

    private var canvas: some View {
        Canvas { ctx, size in
            if let clip { ctx.clip(to: clip) }
            for layer in paint.layers.reversed() {
                PaintRenderer.draw(layer, in: ctx, box: box, area: CGRect(origin: .zero, size: size))
            }
        }
    }
}

enum PaintRenderer {
    static func draw(_ layer: PaintLayer, in ctx: GraphicsContext, box: CGRect, area: CGRect) {
        switch layer {
        case .solid(let c):
            ctx.fill(Path(area), with: .color(Color(c)))

        case .linear(let g):
            let a = g.angle * .pi / 180
            let dir = CGVector(dx: sin(a), dy: -cos(a))
            let length = abs(box.width * sin(a)) + abs(box.height * cos(a))
            let c = CGPoint(x: box.midX, y: box.midY)
            // Repeating gradients are unrolled over the whole area the box could need.
            let lastStop = ThemeContrast.offsets(g.stops, length: length).last ?? length
            let reach = g.repeating == true ? hypot(area.width, area.height) * 2 + length : max(length, lastStop * 2 - length)
            let start = CGPoint(x: c.x - dir.dx * reach / 2, y: c.y - dir.dy * reach / 2)
            let end = CGPoint(x: c.x + dir.dx * reach / 2, y: c.y + dir.dy * reach / 2)
            let gradient = swiftUIGradient(g.stops, length: length, repeating: g.repeating == true,
                                           span: reach, offset: (reach - length) / 2)
            ctx.fill(Path(area), with: .linearGradient(gradient, startPoint: start, endPoint: end))

        case .radial(let g):
            if let tile = g.tile, tile.count == 2, tile[0] > 0, tile[1] > 0 {
                drawTiled(g, tile: CGSize(width: tile[0], height: tile[1]), in: ctx, box: box, area: area)
                return
            }
            drawRadial(g, in: ctx, box: box, area: area)

        case .conic(let g):
            let c = point(g.center, in: box)
            let gradient = swiftUIGradient(g.stops, length: 360, repeating: g.repeating == true, span: 360, offset: 0)
            ctx.fill(Path(area), with: .conicGradient(gradient, center: c, angle: .degrees(g.from - 90)))
        }
    }

    private static func drawRadial(_ g: PaintLayer.Radial, in ctx: GraphicsContext, box: CGRect, area: CGRect) {
        let c = point(g.center, in: box)
        let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)]
        let farthest = corners.map { hypot($0.x - c.x, $0.y - c.y) }.max() ?? box.width
        var rx: CGFloat, ry: CGFloat
        if let size = g.size, !size.isEmpty {
            rx = resolve(size[0], box.width)
            ry = g.shape == .circle ? rx : resolve(size.count > 1 ? size[1] : size[0], box.height)
        } else if g.shape == .circle {
            rx = farthest; ry = farthest
        } else {
            // CSS farthest-corner ellipse: the farthest-side proportions, scaled by √2.
            rx = max(c.x - box.minX, box.maxX - c.x) * 2.squareRoot()
            ry = max(c.y - box.minY, box.maxY - c.y) * 2.squareRoot()
        }
        guard rx > 0, ry > 0 else { return }
        var ctx = ctx
        ctx.translateBy(x: c.x, y: c.y)
        ctx.scaleBy(x: 1, y: ry / rx)
        // The area, in the scaled coordinates.
        let local = CGRect(x: area.minX - c.x, y: (area.minY - c.y) * rx / ry,
                           width: area.width, height: area.height * rx / ry)
        let reach = g.repeating == true
            ? [local.origin, CGPoint(x: local.maxX, y: local.minY), CGPoint(x: local.minX, y: local.maxY),
               CGPoint(x: local.maxX, y: local.maxY)].map { hypot($0.x, $0.y) }.max() ?? rx
            : rx
        // Stops may sit past the nominal radius (a ring at 186.4 pt on a 186 pt circle): reach them too.
        let lastStop = ThemeContrast.offsets(g.stops, length: rx).last ?? rx
        let span = max(reach, rx, lastStop)
        let gradient = swiftUIGradient(g.stops, length: rx, repeating: g.repeating == true, span: span, offset: 0)
        ctx.fill(Path(local), with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: span))
    }

    /// A small radial gradient repeated across the box, like `background-size` (used for star fields).
    private static func drawTiled(_ g: PaintLayer.Radial, tile: CGSize, in ctx: GraphicsContext, box: CGRect, area: CGRect) {
        var single = g
        single.tile = nil
        let lastOpaque = (g.stops.last?.color.a ?? 1) > 0
        let dot = ThemeContrast.offsets(g.stops, length: hypot(tile.width, tile.height) / 2).last ?? 0
        var y = box.minY + floor((area.minY - box.minY) / tile.height) * tile.height
        while y < area.maxY {
            var x = box.minX + floor((area.minX - box.minX) / tile.width) * tile.width
            while x < area.maxX {
                let cell = CGRect(x: x, y: y, width: tile.width, height: tile.height)
                var cellCtx = ctx
                // When the gradient fades out, only its dot needs drawing.
                let region = lastOpaque ? cell
                    : CGRect(x: cell.midX - dot, y: cell.midY - dot, width: dot * 2, height: dot * 2)
                cellCtx.clip(to: Path(region))
                drawRadial(single, in: cellCtx, box: cell, area: region)
                x += tile.width
            }
            y += tile.height
        }
    }

    static func point(_ center: [Length], in box: CGRect) -> CGPoint {
        CGPoint(x: box.minX + resolve(center.first, box.width, default: box.width / 2),
                y: box.minY + resolve(center.count > 1 ? center[1] : nil, box.height, default: box.height / 2))
    }

    static func resolve(_ l: Length?, _ size: CGFloat, default d: CGFloat = 0) -> CGFloat {
        guard let l else { return d }
        return l.unit == .fraction ? l.value * size : l.value
    }

    /// CSS stops (along a gradient line of `length`) as a SwiftUI gradient drawn over `span`, where the
    /// CSS line starts `offset` into the span. Repeating stops are unrolled across the span.
    static func swiftUIGradient(_ stops: [GradientStop], length: Double, repeating: Bool, span: Double, offset: Double) -> Gradient {
        let pos = ThemeContrast.offsets(stops, length: length)
        var out: [(RGBA, Double)] = []
        if repeating, let first = pos.first, let last = pos.last, last - first > 0.01 {
            let period = last - first
            var k = floor((-offset - first) / period)
            while first + k * period + offset <= span {
                for (s, p) in zip(stops, pos) { out.append((s.color, p + k * period + offset)) }
                k += 1
            }
        } else {
            out = zip(stops, pos).map { ($0.color, $1 + offset) }
        }
        return Gradient(stops: premultiplied(out).map {
            Gradient.Stop(color: Color($0.0), location: span > 0 ? $0.1 / span : 0)
        })
    }

    /// CSS fades through transparent without darkening (it interpolates premultiplied colors). Give each
    /// fully transparent stop its neighbours' color, splitting it when the two neighbours differ.
    private static func premultiplied(_ stops: [(RGBA, Double)]) -> [(RGBA, Double)] {
        var out: [(RGBA, Double)] = []
        for (i, (c, p)) in stops.enumerated() {
            guard c.a == 0 else { out.append((c, p)); continue }
            let prev = stops[..<i].last { $0.0.a > 0 }?.0
            let next = stops[(i + 1)...].first { $0.0.a > 0 }?.0
            func clear(_ n: RGBA?) -> RGBA { RGBA(n?.r ?? 0, n?.g ?? 0, n?.b ?? 0, 0) }
            if let prev, let next, prev != next, i > 0, i < stops.count - 1 {
                out.append((clear(prev), p))
                out.append((clear(next), p))
            } else {
                out.append((clear(prev ?? next), p))
            }
        }
        return out
    }
}

// MARK: - Edges

/// Outer shadows of a circle: drop shadows, glows, outline rings and hard offset shadows.
/// Clipped to outside the circle, as CSS does, so a translucent surface isn't darkened by its own shadow.
struct OuterShadows: View, Equatable {
    let shadows: [Shadow]
    let circle: CGRect

    var body: some View {
        Canvas { ctx, size in
            var outside = Path(CGRect(origin: .zero, size: size))
            outside.addEllipse(in: circle)
            ctx.clip(to: outside, style: FillStyle(eoFill: true))
            for s in shadows.reversed() where s.inset != true {
                var c = ctx
                if s.blur > 0 { c.addFilter(.blur(radius: s.blur / 2)) }
                let r = circle.offsetBy(dx: s.x, dy: s.y).insetBy(dx: -(s.spread ?? 0), dy: -(s.spread ?? 0))
                c.fill(Path(ellipseIn: r), with: .color(Color(s.color)))
            }
        }
    }
}

/// Inset shadows and the border of a circle, drawn over its paint.
struct InnerEdge: View, Equatable {
    let edge: RingCore.Edge
    let circle: CGRect

    var body: some View {
        Canvas { ctx, size in
            var inside = ctx
            inside.clip(to: Path(ellipseIn: circle))
            for s in (edge.shadows ?? []).reversed() where s.inset == true {
                var c = inside
                if s.blur > 0 { c.addFilter(.blur(radius: s.blur / 2)) }
                var ring = Path(circle.insetBy(dx: -s.blur * 2 - 40, dy: -s.blur * 2 - 40))
                let spread = s.spread ?? 0
                ring.addEllipse(in: circle.offsetBy(dx: s.x, dy: s.y).insetBy(dx: spread, dy: spread))
                c.fill(ring, with: .color(Color(s.color)), style: FillStyle(eoFill: true))
            }
            if let b = edge.border, b.width > 0 {
                ctx.stroke(Path(ellipseIn: circle.insetBy(dx: b.width / 2, dy: b.width / 2)),
                           with: .color(Color(b.color)), lineWidth: b.width)
            }
        }
    }
}

// MARK: - Rails

extension Rail {
    /// Stroke paint along a rail whose bounding box runs from `minX` to `maxX` in a view `width` wide:
    /// a horizontal gradient across the arc, like the design's SVG gradient.
    func shading(minX: CGFloat, maxX: CGFloat, width: CGFloat) -> AnyShapeStyle {
        let colors = colors.map(Color.init)
        guard colors.count > 1, width > 0 else { return AnyShapeStyle(colors.first ?? .white) }
        return AnyShapeStyle(LinearGradient(colors: colors,
                                            startPoint: UnitPoint(x: minX / width, y: 0.5),
                                            endPoint: UnitPoint(x: maxX / width, y: 0.5)))
    }

    var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: cap == .butt ? .butt : .round)
    }
}

extension View {
    /// Stacked drop shadows (a rail's glow, a label's text-shadow).
    func shadows(_ list: [Shadow]?) -> some View {
        (list ?? []).reduce(AnyView(self)) { view, s in
            AnyView(view.shadow(color: Color(s.color), radius: s.blur / 2, x: s.x, y: s.y))
        }
    }

    /// A looping idle effect while `active`; nothing when nil or inactive.
    func idle(_ idle: Idle?, active: Bool) -> some View {
        modifier(IdleEffect(idle: idle, active: active))
    }
}

/// Neon flicker, pulse and glitch for rails; spin is handled by the disk.
struct IdleEffect: ViewModifier {
    let idle: Idle?
    let active: Bool

    func body(content: Content) -> some View {
        if let idle, idle.kind != .spin, active {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: idle.period) / idle.period
                let (opacity, offset) = Self.frame(idle.kind, phase)
                content.opacity(opacity).offset(offset)
            }
        } else {
            content
        }
    }

    /// Opacity and offset at `phase` (0–1) of a cycle, matching the design's keyframes.
    static func frame(_ kind: Idle.Kind, _ phase: Double) -> (Double, CGSize) {
        switch kind {
        case .flicker:
            // Full on, with brief dips to 0.3 around 19–21% and 62%.
            let dips: [(Double, Double)] = [(0.18, 0.20), (0.20, 0.22), (0.61, 0.63)]
            for (from, to) in dips where phase >= from && phase <= to {
                let mid = (from + to) / 2
                return (1 - 0.7 * (1 - abs(phase - mid) / (mid - from)), .zero)
            }
            return (1, .zero)
        case .pulse:
            return (0.86 + 0.14 * cos(phase * 2 * .pi), .zero)
        case .glitch:
            if phase >= 0.91 && phase < 0.93 { return (1, CGSize(width: 3, height: 0)) }
            if phase >= 0.93 && phase < 0.95 { return (1, CGSize(width: -2, height: 1)) }
            return (1, .zero)
        case .spin:
            return (1, .zero)
        }
    }
}

// MARK: - Fonts

/// A theme font, falling back to a similar macOS font, then the system font, when it isn't installed.
struct ThemeFont {
    let font: Font
    /// Letter spacing in points.
    let tracking: CGFloat
    let uppercase: Bool
    let shadows: [Shadow]?

    /// macOS fonts close to the design's Google Fonts, used until those are bundled.
    static let substitutes: [String: [String]] = [
        "Bodoni Moda": ["Bodoni 72", "Didot"],
        "Cinzel": ["Trajan Pro", "Copperplate"],
        "Cormorant Garamond": ["Hoefler Text", "Baskerville"],
        "Orbitron": ["Futura"],
        "Bungee": ["Arial Black"],
        "Tilt Neon": ["Arial Rounded MT Bold"],
    ]

    private static let installed = Set(NSFontManager.shared.availableFontFamilies)

    init(_ spec: FontSpec?, defaultSize: CGFloat, defaultWeight: Font.Weight) {
        guard let spec else {
            font = .system(size: defaultSize, weight: defaultWeight)
            tracking = 0; uppercase = false; shadows = nil
            return
        }
        let weight = Self.weight(spec.weight)
        let family = ([spec.family] + (Self.substitutes[spec.family] ?? [])).first { Self.installed.contains($0) }
        var font = family.map { Font.custom($0, size: spec.size).weight(weight) } ?? .system(size: spec.size, weight: weight)
        if spec.italic == true { font = font.italic() }
        self.font = font
        tracking = (spec.tracking ?? 0) * spec.size
        uppercase = spec.uppercase == true
        shadows = spec.shadows
    }

    private static func weight(_ w: Int) -> Font.Weight {
        switch w {
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        default: .heavy
        }
    }
}

extension Text {
    init(_ string: String, themed font: ThemeFont) {
        self.init(font.uppercase ? string.uppercased() : string)
    }
}

// MARK: - Spin

extension View {
    /// Turns once per period while `active` (the Astrolabe's orbits).
    func spin(_ idle: Idle?, active: Bool) -> some View {
        modifier(SpinEffect(period: idle?.kind == .spin ? idle?.period : nil, active: active))
    }
}

struct SpinEffect: ViewModifier {
    let period: Double?
    let active: Bool

    func body(content: Content) -> some View {
        if let period, period > 0, active {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let turns = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                content.rotationEffect(.degrees(turns * 360))
            }
        } else {
            content
        }
    }
}
