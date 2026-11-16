import Foundation

/// How readable a theme's labels are on a hovered sub-action, all the way around the wheel.
///
/// The hover paint spans the whole wheel (the design's 720 pt box) and is clipped to the hovered
/// sub-action, so the color behind a label depends on where it sits. This samples the paint where
/// the label goes, every 5°, composited over the resting sub-action and a black (dark theme) or
/// white (light theme) desktop. Mirrors `design/tools/contrast.py`.
public enum ThemeContrast {
    /// Side of the box the wheel-wide paints span, as in the design.
    public static let paintBox: Double = 720
    /// Distance of a sub-action's label from the center.
    public static let labelRadius: Double = 249

    /// The lowest WCAG contrast of `onHover` on `subHover`, and the angle (degrees, 0 = top) where it happens.
    public static func worstHoveredLabel(_ t: ThemeSpec) -> (ratio: Double, angle: Double) {
        let desktop = t.isDark ? RGBA.black : RGBA.white
        let resting = sample(t.sub, x: paintBox / 2, y: paintBox / 2 - labelRadius, under: desktop)
        var worst = (ratio: Double.infinity, angle: 0.0)
        for deg in stride(from: 0.0, to: 360, by: 5) {
            let a = deg * .pi / 180
            let x = paintBox / 2 + labelRadius * sin(a), y = paintBox / 2 - labelRadius * cos(a)
            let fill = sample(t.subHover, x: x, y: y, under: resting)
            let ratio = RGBA.contrast(t.onHover.over(fill), fill)
            if ratio < worst.ratio { worst = (ratio, deg) }
        }
        return worst
    }

    /// The opaque color of `paint` at (x, y) in the paint box, laid over `under`.
    public static func sample(_ paint: Paint, x: Double, y: Double, under: RGBA) -> RGBA {
        paint.layers.reversed().reduce(under) { below, layer in color(of: layer, x: x, y: y).over(below) }
    }

    static func color(of layer: PaintLayer, x: Double, y: Double) -> RGBA {
        let box = paintBox
        switch layer {
        case .solid(let c):
            return c
        case .linear(let g):
            let a = g.angle * .pi / 180
            let total = abs(box * sin(a)) + abs(box * cos(a))
            let t = total / 2 + (x - box / 2) * sin(a) - (y - box / 2) * cos(a)
            return color(g.stops, at: t, length: total, repeating: g.repeating == true)
        case .radial(let g):
            let cx = resolve(g.center.first, box, default: box / 2)
            let cy = resolve(g.center.count > 1 ? g.center[1] : nil, box, default: box / 2)
            let corner = [(0.0, 0.0), (box, 0), (0, box), (box, box)].map { hypot($0.0 - cx, $0.1 - cy) }.max() ?? box
            let rx = resolve(g.size?.first, box, default: corner)
            let ry = g.shape == .circle ? rx : resolve(g.size.flatMap { $0.count > 1 ? $0[1] : nil }, box, default: corner)
            let t = hypot((x - cx) / rx, (y - cy) / ry) * rx
            return color(g.stops, at: t, length: rx, repeating: g.repeating == true)
        case .conic(let g):
            let cx = resolve(g.center.first, box, default: box / 2)
            let cy = resolve(g.center.count > 1 ? g.center[1] : nil, box, default: box / 2)
            var deg = atan2(x - cx, cy - y) * 180 / .pi - g.from
            deg = deg.truncatingRemainder(dividingBy: 360)
            if deg < 0 { deg += 360 }
            return color(g.stops, at: deg, length: 360, repeating: g.repeating == true)
        }
    }

    private static func resolve(_ l: Length?, _ box: Double, default d: Double) -> Double {
        guard let l else { return d }
        return l.unit == .fraction ? l.value * box : l.value
    }

    /// Stop offsets along a gradient line of `length`, spreading unplaced stops evenly as CSS does.
    public static func offsets(_ stops: [GradientStop], length: Double) -> [Double] {
        var pos: [Double?] = stops.map { s in s.at.map { $0.unit == .fraction ? $0.value * length : $0.value } }
        guard !pos.isEmpty else { return [] }
        if pos[0] == nil { pos[0] = 0 }
        if pos[pos.count - 1] == nil { pos[pos.count - 1] = length }
        var i = 1
        while i < pos.count {
            if pos[i] == nil {
                var j = i
                while pos[j] == nil { j += 1 }
                let (from, to) = (pos[i - 1]!, pos[j]!)
                for k in i..<j { pos[k] = from + (to - from) * Double(k - i + 1) / Double(j - i + 1) }
                i = j
            }
            i += 1
        }
        // CSS: a stop placed before an earlier one moves up to it.
        var out: [Double] = []
        for p in pos.map({ $0! }) { out.append(max(p, out.last ?? p)) }
        return out
    }

    static func color(_ stops: [GradientStop], at t: Double, length: Double, repeating: Bool) -> RGBA {
        let pos = offsets(stops, length: length)
        guard let first = pos.first, let last = pos.last else { return .clear }
        var t = t
        if repeating, last > first {
            t = first + (t - first).truncatingRemainder(dividingBy: last - first)
            if t < first { t += last - first }
        }
        if t <= first { return stops[0].color }
        for i in 0..<(pos.count - 1) where t <= pos[i + 1] {
            let span = pos[i + 1] - pos[i]
            let f = span > 0 ? (t - pos[i]) / span : 1
            let (a, b) = (stops[i].color, stops[i + 1].color)
            return RGBA(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, a.a + (b.a - a.a) * f)
        }
        return stops[stops.count - 1].color
    }
}
