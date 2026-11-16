import Foundation

// A theme as data: every color, gradient, edge, rail and font the wheel draws with. The built-in
// themes live in `design/themes/themes.json` (embedded in `BuiltInThemes.swift`); the app turns a
// spec into SwiftUI styles. Values follow CSS where CSS has a word for it, so the design tool's
// output converts one-to-one:
// - colors are RGB in 0–1 plus alpha;
// - angles are CSS degrees (0 = towards the top, 90 = towards the right);
// - shadow `blur` is the CSS blur radius (SwiftUI's shadow radius is about half of it);
// - lengths are points ("22pt"), fractions of the painted box ("55%") or angles ("9deg").

public struct RGBA: Codable, Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        r = try c.decode(Double.self, forKey: .r)
        g = try c.decode(Double.self, forKey: .g)
        b = try c.decode(Double.self, forKey: .b)
        a = try c.decodeIfPresent(Double.self, forKey: .a) ?? 1
    }

    /// Relative luminance (WCAG 2), ignoring alpha.
    public var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// This color laid over an opaque `background`.
    public func over(_ background: RGBA) -> RGBA {
        RGBA(r * a + background.r * (1 - a), g * a + background.g * (1 - a), b * a + background.b * (1 - a), 1)
    }

    /// WCAG contrast ratio between two opaque colors (1–21).
    public static func contrast(_ x: RGBA, _ y: RGBA) -> Double {
        let (l1, l2) = (max(x.luminance, y.luminance), min(x.luminance, y.luminance))
        return (l1 + 0.05) / (l2 + 0.05)
    }

    public static let black = RGBA(0, 0, 0)
    public static let white = RGBA(1, 1, 1)
    public static let clear = RGBA(0, 0, 0, 0)
}

/// A length in points, a fraction of the painted box, or an angle. Encoded as "22pt", "55%" or "9deg".
public struct Length: Codable, Equatable, Sendable {
    public enum Unit: String, Sendable { case pt, fraction = "%", deg }
    /// Points, a fraction (0–1, written as a percentage), or degrees.
    public var value: Double
    public var unit: Unit

    public init(_ value: Double, _ unit: Unit) {
        self.value = value; self.unit = unit
    }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        for unit in [Unit.pt, .fraction, .deg] where s.hasSuffix(unit.rawValue) {
            if let v = Double(s.dropLast(unit.rawValue.count)) {
                self.init(unit == .fraction ? v / 100 : v, unit)
                return
            }
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad length \(s)"))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        var s = String(format: "%.3f", unit == .fraction ? value * 100 : value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        try c.encode(s + unit.rawValue)
    }
}

public struct GradientStop: Codable, Equatable, Sendable {
    public var color: RGBA
    /// Nil: spread evenly between its neighbours, as in CSS.
    public var at: Length?
}

/// One layer of a paint. Layers stack like CSS backgrounds: the first is on top.
public enum PaintLayer: Codable, Equatable, Sendable {
    case solid(RGBA)
    case linear(Linear)
    case radial(Radial)
    case conic(Conic)

    public struct Linear: Codable, Equatable, Sendable {
        /// CSS angle: 180 runs top to bottom, 135 top-left to bottom-right.
        public var angle: Double
        public var stops: [GradientStop]
        public var repeating: Bool?
    }

    public struct Radial: Codable, Equatable, Sendable {
        public enum Shape: String, Codable, Sendable { case circle, ellipse }
        public var shape: Shape
        /// Radius (circle) or the two radii (ellipse); nil reaches the farthest corner.
        public var size: [Length]?
        /// Center as x, y; usually fractions of the box.
        public var center: [Length]
        public var stops: [GradientStop]
        public var repeating: Bool?
        /// Repeat the gradient in tiles of this many points (width, height).
        public var tile: [Double]?
    }

    public struct Conic: Codable, Equatable, Sendable {
        /// CSS start angle (0 = up, clockwise).
        public var from: Double
        public var center: [Length]
        public var stops: [GradientStop]
        public var repeating: Bool?
    }

    private enum CodingKeys: String, CodingKey { case solid, linear, radial, conic }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(RGBA.self, forKey: .solid) { self = .solid(v) }
        else if let v = try c.decodeIfPresent(Linear.self, forKey: .linear) { self = .linear(v) }
        else if let v = try c.decodeIfPresent(Radial.self, forKey: .radial) { self = .radial(v) }
        else if let v = try c.decodeIfPresent(Conic.self, forKey: .conic) { self = .conic(v) }
        else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown paint layer")) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .solid(let v): try c.encode(v, forKey: .solid)
        case .linear(let v): try c.encode(v, forKey: .linear)
        case .radial(let v): try c.encode(v, forKey: .radial)
        case .conic(let v): try c.encode(v, forKey: .conic)
        }
    }

    public var stops: [GradientStop] {
        switch self {
        case .solid(let c): [GradientStop(color: c, at: nil)]
        case .linear(let g): g.stops
        case .radial(let g): g.stops
        case .conic(let g): g.stops
        }
    }
}

/// A fill: one color, or layers of gradients (top first). Encoded as a bare color when it's one color.
public struct Paint: Codable, Equatable, Sendable {
    public var layers: [PaintLayer]

    public init(_ layers: [PaintLayer]) { self.layers = layers }
    public init(_ color: RGBA) { layers = [.solid(color)] }

    public init(from decoder: Decoder) throws {
        if let color = try? RGBA(from: decoder) {
            layers = [.solid(color)]
        } else {
            layers = try [PaintLayer](from: decoder)
        }
    }

    public func encode(to encoder: Encoder) throws {
        if layers.count == 1, case .solid(let c) = layers[0] { try c.encode(to: encoder) } else { try layers.encode(to: encoder) }
    }

    /// The colors of the bottom layer, the one the paint mostly reads as.
    public var baseColors: [RGBA] { layers.last?.stops.map(\.color) ?? [] }
}

public struct Shadow: Codable, Equatable, Sendable {
    public var color: RGBA
    public var x: Double
    public var y: Double
    /// CSS blur radius.
    public var blur: Double
    public var spread: Double?
    public var inset: Bool?

    public init(color: RGBA, x: Double = 0, y: Double = 0, blur: Double, spread: Double? = nil, inset: Bool? = nil) {
        self.color = color; self.x = x; self.y = y; self.blur = blur; self.spread = spread; self.inset = inset
    }
}

/// Outline and shadows of a round surface (the disk or the hub).
public struct Edge: Codable, Equatable, Sendable {
    public struct Border: Codable, Equatable, Sendable {
        public var width: Double
        public var color: RGBA
    }
    public var border: Border?
    /// Outer drop shadows, glows, hard offset shadows, outline rings (`spread` with no blur) and inset shades.
    public var shadows: [Shadow]?
}

/// A slow, looping effect while the wheel is open. Off under Reduce Motion.
public struct Idle: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Turns the whole layer once per period.
        case spin
        /// Neon-sign flicker: brief dips in brightness.
        case flicker
        /// Breathes between full and ~70% brightness.
        case pulse
        /// Jumps a few points sideways now and then.
        case glitch
    }
    public var kind: Kind
    /// Seconds per cycle.
    public var period: Double
}

/// The selection rails (and the Settings arm ring).
public struct Rail: Codable, Equatable, Sendable {
    public enum Cap: String, Codable, Sendable { case round, butt }
    /// One color, or two for a gradient along the rail.
    public var colors: [RGBA]
    public var width: Double
    public var cap: Cap
    /// Drop shadows stacked into a glow.
    public var glow: [Shadow]?
    public var idle: Idle?
}

public struct FontSpec: Codable, Equatable, Sendable {
    /// Family name, e.g. "Orbitron". The app falls back to the system font when it isn't available.
    public var family: String
    public var size: Double
    public var weight: Int
    public var italic: Bool?
    /// Letter spacing in em.
    public var tracking: Double?
    public var uppercase: Bool?
    public var shadows: [Shadow]?
}

public struct BackdropSpec: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case blur, glass }
    public var kind: Kind
    public var dark: Bool
}

public struct ThemeSpec: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Grouping such as "fire" or "neon", when the theme belongs to one.
    public var family: String?
    public var description: String?
    /// Background the design previewed it on: "dusk", "bright" or "window".
    public var preview: String?

    public var backdrop: BackdropSpec
    /// Tint over the backdrop, filling the disk.
    public var disk: Paint
    public var diskEdge: Edge
    public var diskIdle: Idle?
    /// A slice wedge at rest, and hovered. Painted across the whole wheel, clipped to the wedge.
    public var slice: Paint
    public var sliceHover: Paint
    /// Soft glow under the hovered slice.
    public var halo: RGBA?
    public var rail: Rail
    public var hub: Paint
    public var hubEdge: Edge
    /// Hub while letting go there would open Settings.
    public var hubHover: Paint
    /// Hub title and primary labels; captions.
    public var text: RGBA
    public var subtext: RGBA
    /// A sub-action wedge at rest, and hovered. Painted across the whole wheel, clipped to the wedge.
    public var sub: Paint
    public var subHover: Paint
    /// Icons and labels at rest.
    public var symbol: RGBA
    /// Icons and labels on `subHover`.
    public var onHover: RGBA
    /// Hub title, and sub-action labels.
    public var hubFont: FontSpec?
    public var labelFont: FontSpec?

    public var isDark: Bool { backdrop.dark }
}

public enum ThemeCatalog {
    /// Every built-in theme, light ones first.
    public static let builtIn: [ThemeSpec] = {
        do {
            return try JSONDecoder().decode([ThemeSpec].self, from: Data(BuiltInThemes.json.utf8))
        } catch {
            assertionFailure("Built-in themes don't decode: \(error)")
            return []
        }
    }()

    public static func named(_ id: String) -> ThemeSpec? { builtIn.first { $0.id == id } }
}
