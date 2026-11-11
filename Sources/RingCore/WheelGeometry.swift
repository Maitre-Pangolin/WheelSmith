import Foundation

/// Radii (points) of the wheel's rings, from the center outwards.
public struct WheelMetrics: Equatable, Sendable {
    /// Center hub: releasing here opens Settings.
    public var hubRadius: Double = 44
    /// Slice band.
    public var ringInner: Double = 52
    public var ringOuter: Double = 148
    /// Sub-action band, shown around the hovered slice when it has children.
    public var subInner: Double = 156
    public var subOuter: Double = 236
    /// Forgiveness band beyond the outer edge before a release counts as "cancel".
    public var cancelSlack: Double = 26
    /// Angular width of one sub-action (radians).
    public var childSpan: Double = 34 * .pi / 180

    public static let standard = WheelMetrics()

    public init() {}

    /// Side of the square canvas the wheel is drawn in.
    public var canvasSize: Double { 2 * (subOuter + 28) }
}

/// What the pointer is over.
public enum WheelHit: Equatable, Sendable {
    case center
    case item(Int)
    case child(Int, Int)
    case cancel

    /// The top-level slice involved, if any.
    public var itemIndex: Int? {
        switch self {
        case .item(let i), .child(let i, _): i
        case .center, .cancel: nil
        }
    }
}

/// Pure hit-testing math. Angles: 0 = straight up, increasing clockwise, in [0, 2π).
/// `dx`/`dy` are offsets from the wheel center with y pointing UP (Cocoa screen coordinates).
public struct WheelGeometry: Equatable, Sendable {
    public var metrics: WheelMetrics
    /// Number of children for each slice; its count is the number of slices.
    public var childCounts: [Int]

    public init(childCounts: [Int], metrics: WheelMetrics = .standard) {
        self.childCounts = childCounts
        self.metrics = metrics
    }

    public var count: Int { childCounts.count }
    public var sliceSpan: Double { count > 0 ? 2 * .pi / Double(count) : 2 * .pi }

    public static func angle(dx: Double, dy: Double) -> Double {
        let a = atan2(dx, dy)
        return a < 0 ? a + 2 * .pi : a
    }

    public static func angularDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi)
        return min(d, 2 * .pi - d)
    }

    public func sliceCenter(_ i: Int) -> Double { Double(i) * sliceSpan }

    public func slice(at angle: Double) -> Int {
        guard count > 0 else { return 0 }
        let shifted = (angle + sliceSpan / 2).truncatingRemainder(dividingBy: 2 * .pi)
        return min(Int(shifted / sliceSpan), count - 1)
    }

    /// Centers of the sub-action sectors of slice `parent`, fanned around the slice's center.
    public func childAngles(parent: Int) -> [Double] {
        guard parent < count else { return [] }
        let n = childCounts[parent]
        let start = sliceCenter(parent) - Double(n - 1) * metrics.childSpan / 2
        return (0..<n).map { j in
            let a = start + Double(j) * metrics.childSpan
            return a < 0 ? a + 2 * .pi : a.truncatingRemainder(dividingBy: 2 * .pi)
        }
    }

    /// How far from the center, to the right (`side` 1) or left (-1), a box vertically centered on the
    /// wheel and `halfHeight` tall each way must start to clear the slice disk and the open sub-ring.
    public func horizontalClearance(halfHeight: Double, openParent: Int?, side: Double = 1) -> Double {
        var clearance = metrics.ringOuter
        guard let p = openParent, p < count, childCounts[p] > 0 else { return clearance }
        let steps = 16
        for a in childAngles(parent: p) {
            for i in 0...steps {
                let theta = a - metrics.childSpan / 2 + Double(i) * metrics.childSpan / Double(steps)
                for k in 0...4 {
                    let r = metrics.subInner + Double(k) * (metrics.subOuter - metrics.subInner) / 4
                    let x = r * sin(theta) * side, y = r * cos(theta)
                    if x > 0, abs(y) <= halfHeight { clearance = max(clearance, x) }
                }
            }
        }
        return clearance
    }

    public func hit(dx: Double, dy: Double, openParent: Int?) -> WheelHit {
        let r = (dx * dx + dy * dy).squareRoot()
        if r < metrics.hubRadius { return .center }
        guard count > 0 else { return .cancel }
        let a = Self.angle(dx: dx, dy: dy)
        if r <= metrics.ringOuter { return .item(slice(at: a)) }

        // Beyond the slice band: sub-actions of the open slice take priority.
        if let p = openParent, p < count, childCounts[p] > 0, r <= metrics.subOuter + metrics.cancelSlack {
            let angles = childAngles(parent: p)
            if let (j, d) = angles.enumerated()
                .map({ ($0.offset, Self.angularDistance($0.element, a)) })
                .min(by: { $0.1 < $1.1 }),
               d <= metrics.childSpan * 0.75 {
                return .child(p, j)
            }
        }
        if r <= metrics.ringOuter + metrics.cancelSlack { return .item(slice(at: a)) }
        return .cancel
    }
}

/// Stateful tracker: remembers which slice's sub-actions are open while the pointer travels outwards.
public struct WheelTracker: Equatable, Sendable {
    public var geometry: WheelGeometry
    public private(set) var openParent: Int?
    public private(set) var hit: WheelHit = .center

    public init(geometry: WheelGeometry) {
        self.geometry = geometry
    }

    public mutating func reset() {
        openParent = nil
        hit = .center
    }

    @discardableResult
    public mutating func update(dx: Double, dy: Double) -> WheelHit {
        hit = geometry.hit(dx: dx, dy: dy, openParent: openParent)
        switch hit {
        case .center: openParent = nil
        case .item(let i): openParent = geometry.childCounts[i] > 0 ? i : nil
        case .child, .cancel: break
        }
        return hit
    }
}
