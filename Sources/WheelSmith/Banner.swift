import AppKit
import SwiftUI
import RingCore

/// `WheelSmith --banner <dir>`: renders the README banners, each in a light and a dark version.
/// The wheel is the real `WheelCanvas`, drawn with a neutral set of apps.
@MainActor
enum Banner {
    static let size = CGSize(width: 1280, height: 320)

    /// The layout every banner shares: half a wheel coming in from the left edge, Slack's outer ring
    /// fanned out towards a glowing Tilt Neon wordmark.
    static let center = CGPoint(x: 70, y: 160)
    static let scale: CGFloat = 0.78
    static let hit = WheelHit.child(2, 1)
    static let parent = 2
    static let textX: CGFloat = 520

    /// A light and a dark theme shown in the same layout.
    struct Pair {
        let id: String
        let dark: Look
        let light: Look
    }

    struct Look {
        let theme: String
        /// The color of "Smith" and the glow; nil uses the theme's hovered sub-action, adjusted for contrast.
        var accent: Color? = nil

        init(_ theme: String, accent: Color? = nil) {
            self.theme = theme
            self.accent = accent
        }
    }

    static let pairs: [Pair] = [
        Pair(id: "neon", dark: Look("neon-sign"), light: Look("highlighter", accent: Color(hex: 0xE0338A))),
        Pair(id: "original", dark: Look("midnight"), light: Look("daylight")),
        Pair(id: "graphite", dark: Look("graphite", accent: Color(hex: 0xA9B6CC)), light: Look("porcelain")),
        Pair(id: "fire", dark: Look("magma"), light: Look("sunfire")),
        Pair(id: "ice", dark: Look("polar-night", accent: Color(hex: 0x7FD3F0)), light: Look("glacier")),
        Pair(id: "earth", dark: Look("moss"), light: Look("meadow")),
        Pair(id: "golden", dark: Look("forged-gold"), light: Look("elvenlight", accent: Color(hex: 0x9C6F16))),
        Pair(id: "astral", dark: Look("astrolabe", accent: Color(hex: 0x9FD4DC)), light: Look("celestial", accent: Color(hex: 0x4F7F96))),
        Pair(id: "cyberpunk", dark: Look("night-city", accent: Color(hex: 0xFF3D7F)), light: Look("chrome-day", accent: Color(hex: 0xC9A800))),
        Pair(id: "glossy", dark: Look("lacquer"), light: Look("pearl")),
    ]

    /// The showcase wheel with apps most people have: Chrome instead of Dia, Notes instead of Ostraka.
    static var items: [WheelItem] {
        let chrome = "com.google.Chrome", notes = "com.apple.Notes"
        return DefaultConfig.showcase.items.map { item in
            switch item.label {
            case "Dia":
                WheelItem(label: "Chrome", action: .app(bundleId: chrome), children: [
                    WheelItem(label: "New tab", icon: "sf:plus.square.on.square", action: .keys("cmd+t", bundleId: chrome)),
                    WheelItem(label: "New window", icon: "sf:macwindow.badge.plus", action: .keys("cmd+n", bundleId: chrome)),
                ])
            case "Ostraka":
                WheelItem(label: "Notes", action: .app(bundleId: notes), children: [
                    WheelItem(label: "New note", icon: "sf:square.and.pencil", action: .keys("cmd+n", bundleId: notes)),
                ])
            default: item
            }
        }
    }

    static func run(outputDirectory: String, only: Set<String>? = nil) {
        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let items = items
        IconCache.shared.preload(items)
        for pair in pairs where only?.contains(pair.id) ?? true {
            for (mode, look) in [("dark", pair.dark), ("light", pair.light)] {
                render(BannerView(look: look, items: items), size: size,
                       to: dir.appendingPathComponent("banner-\(pair.id)-\(mode).png"))
            }
        }
        print("Banners written to \(dir.path)")
    }

    /// Like the snapshot renderer, but keeps the transparent corners.
    private static func render<V: View>(_ view: V, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

private struct BannerView: View {
    let look: Banner.Look
    let items: [WheelItem]

    private var theme: Theme { Theme.named(look.theme) }
    /// How far the background, halo and shadow set the wheel apart, from 0 to 1. The dark wheel needs
    /// more help than the light one, which already reads against a near-white page.
    private var contrast: CGFloat { theme.isDark ? 1 : 1 / 3 }

    /// The hovered sub-action's color, nudged until it reads against the background.
    private var accent: Color {
        if let accent = look.accent { return accent }
        var color = NSColor(theme.subHover.first ?? theme.rail).usingColorSpace(.sRGB) ?? .white
        for _ in 0..<8 {
            let l = color.luminance
            if theme.isDark ? l >= 0.2 : l <= 0.3 { break }
            color = color.blended(withFraction: 0.15, of: theme.isDark ? .white : .black) ?? color
        }
        return Color(nsColor: color)
    }

    /// A theme color as banner text: kept when it reads on the background, else plain white or near-black.
    private func readable(_ color: Color, dim: Bool = false) -> Color {
        let l = (NSColor(color).usingColorSpace(.sRGB) ?? .white).luminance
        if theme.isDark ? l >= 0.35 : l <= 0.25 { return color }
        return theme.isDark ? .white.opacity(dim ? 0.6 : 1) : Color(hex: 0x15161A).opacity(dim ? 0.6 : 1)
    }

    /// Near-black or near-white, tinted with the accent.
    private var background: [Color] {
        let tint = NSColor(accent)
        func mix(_ base: UInt32, _ amount: CGFloat) -> Color {
            Color(nsColor: NSColor(Color(hex: base)).blended(withFraction: amount, of: tint) ?? NSColor(Color(hex: base)))
        }
        func step(_ from: UInt32, _ to: UInt32) -> UInt32 {
            let a = NSColor(Color(hex: from)).usingColorSpace(.sRGB)!, b = NSColor(Color(hex: to)).usingColorSpace(.sRGB)!
            let c = a.blended(withFraction: contrast, of: b)!
            return UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255)
        }
        // Dark: lift the background off the dark wheel. Light: deepen it behind the white wheel.
        return theme.isDark
            ? [mix(step(0x0E0E12, 0x2C2F37), 0.12), mix(step(0x040406, 0x15171C), 0.04)]
            : [mix(step(0xFFFFFF, 0xE4E7EC), 0.04), mix(step(0xF0F1F4, 0xC9CED8), 0.1)]
    }

    var body: some View {
        let side = WheelMetrics.standard.canvasSize
        let accent = accent
        let glow = theme.isDark ? (0.8, 0.5) : (0.45, 0.25)
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: background, startPoint: .top, endPoint: .bottom)
            // A soft halo of the accent just around the wheel's rim.
            RadialGradient(colors: [accent.opacity((theme.isDark ? 0.16 : 0.1) * contrast), .clear],
                           center: UnitPoint(x: Banner.center.x / Banner.size.width, y: Banner.center.y / Banner.size.height),
                           startRadius: 150, endRadius: 360)
            WheelCanvas(items: items, theme: theme, hit: Banner.hit, openParent: Banner.parent, opaqueBackdrop: true,
                        armProgress: 0)
                .frame(width: side, height: side)
                .scaleEffect(Banner.scale)
                .shadow(color: .black.opacity((theme.isDark ? 0.5 : 0.14) * contrast), radius: 24, x: 4, y: 6)
                .position(Banner.center)
            VStack(alignment: .leading, spacing: 10) {
                // Only the colored half glows.
                HStack(spacing: 0) {
                    Text("Wheel").foregroundStyle(readable(theme.text))
                    Text("Smith").foregroundStyle(accent)
                        .shadow(color: accent.opacity(glow.0), radius: 14)
                        .shadow(color: accent.opacity(glow.1), radius: 30)
                }
                .font(.custom("Tilt Neon", size: 92))
                Text("A quick-action wheel for macOS")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(readable(theme.text).opacity(0.85))
                Text("Hold ⌥ Space  ·  point  ·  let go")
                    .font(.system(size: 19, weight: .regular, design: .rounded))
                    .foregroundStyle(readable(theme.subtext, dim: true))
                    .padding(.top, 2)
            }
            .padding(.leading, Banner.textX)
            .frame(maxHeight: .infinity)
        }
        .frame(width: Banner.size.width, height: Banner.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
    }
}

private extension NSColor {
    /// Relative luminance (WCAG), for an sRGB color.
    var luminance: CGFloat {
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(redComponent) + 0.7152 * lin(greenComponent) + 0.0722 * lin(blueComponent)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
