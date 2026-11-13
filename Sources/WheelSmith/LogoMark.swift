import CoreGraphics
import Foundation

/// The WheelSmith mark: a ring with one segment raised out of it, like a wheel slice under the pointer.
/// Pure CoreGraphics so the menu bar icon and `scripts/make-icon.swift` draw the exact same shape.
struct LogoMark {
    /// Radius of the ring's centerline, as a fraction of the canvas side.
    var ringRadius: CGFloat = 0.30
    /// Ring thickness, as a fraction of the canvas side.
    var ringWidth: CGFloat = 0.12
    /// Direction the raised segment points to, in degrees (0 = right, 90 = up).
    var direction: CGFloat = 45
    /// Angular size of the raised segment, in degrees.
    var span: CGFloat = 72
    /// Width of the cut on each side of the segment, as a fraction of the canvas side.
    var gap: CGFloat = 0.06
    /// How far the segment is pushed outward, as a fraction of the canvas side.
    var raise: CGFloat = 0.06
    /// Extra thickness the segment gains outward, as a fraction of the canvas side.
    var grow: CGFloat = 0.04

    /// The whole mark filling `rect` (a square), in y-up coordinates.
    func path(in rect: CGRect) -> CGPath {
        let (ring, segment) = parts(in: rect)
        let path = CGMutablePath()
        path.addPath(ring)
        path.addPath(segment)
        return path
    }

    /// The ring (minus the segment and its cuts) and the raised segment, separately, so they can be
    /// painted differently.
    func parts(in rect: CGRect) -> (ring: CGPath, segment: CGPath) {
        let side = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = ringRadius * side, w = ringWidth * side
        let half = span * .pi / 360, dir = direction * .pi / 180
        // Keep the cut a constant width rather than a constant angle.
        let cut = (gap * side / 2) / r

        let ring = CGMutablePath()
        addSector(to: ring, center: c, inner: r - w / 2, outer: r + w / 2,
                  from: dir + half + cut, to: dir - half - cut + 2 * .pi)
        let lift = raise * side
        let segment = CGMutablePath()
        addSector(to: segment, center: c, inner: r - w / 2 + lift, outer: r + w / 2 + lift + grow * side,
                  from: dir - half + cut * r / (r + lift), to: dir + half - cut * r / (r + lift))
        return (ring, segment)
    }

    private func addSector(to path: CGMutablePath, center c: CGPoint, inner: CGFloat, outer: CGFloat,
                           from a0: CGFloat, to a1: CGFloat) {
        // Start a fresh subpath: addArc would otherwise draw a line from the previous shape.
        path.move(to: CGPoint(x: c.x + outer * cos(a0), y: c.y + outer * sin(a0)))
        path.addArc(center: c, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
        path.addArc(center: c, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
        path.closeSubpath()
    }
}
