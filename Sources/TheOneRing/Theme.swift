import SwiftUI
import AppKit

/// Every color the wheel uses lives here, so new themes are just new values.
struct Theme: Identifiable {
    enum Backdrop {
        /// Blurs whatever is behind the wheel.
        case blur(NSVisualEffectView.Material, dark: Bool)
        /// macOS 26 Liquid Glass (falls back to blur on older systems).
        case glass(dark: Bool)
    }

    let id: String
    let name: String
    let backdrop: Backdrop
    /// Tint laid over the backdrop.
    let disk: Color
    let stroke: Color
    let slice: Color
    let sliceHover: [Color]
    let glow: Color
    let hub: Color
    let text: Color
    let subtext: Color
    /// Fill of the sub-action ring.
    let sub: Color
    let symbol: Color
    let shadow: Color

    var isDark: Bool {
        switch backdrop {
        case .blur(_, let dark), .glass(let dark): dark
        }
    }

    static let midnight = Theme(
        id: "midnight", name: "Midnight",
        backdrop: .blur(.hudWindow, dark: true),
        disk: Color(red: 0.04, green: 0.04, blue: 0.08).opacity(0.62),
        stroke: .white.opacity(0.10),
        slice: .white.opacity(0.045),
        sliceHover: [Color(red: 0.49, green: 0.36, blue: 1.0), Color(red: 0.18, green: 0.62, blue: 1.0)],
        glow: Color(red: 0.36, green: 0.48, blue: 1.0),
        hub: Color(red: 0.09, green: 0.09, blue: 0.13).opacity(0.92),
        text: .white,
        subtext: .white.opacity(0.55),
        sub: Color(red: 0.07, green: 0.07, blue: 0.11).opacity(0.94),
        symbol: .white.opacity(0.92),
        shadow: .black.opacity(0.45)
    )

    static let daylight = Theme(
        id: "daylight", name: "Daylight",
        backdrop: .blur(.popover, dark: false),
        disk: .white.opacity(0.55),
        stroke: .black.opacity(0.08),
        slice: .black.opacity(0.035),
        sliceHover: [Color(red: 1.0, green: 0.52, blue: 0.30), Color(red: 1.0, green: 0.30, blue: 0.45)],
        glow: Color(red: 1.0, green: 0.42, blue: 0.38),
        hub: .white.opacity(0.92),
        text: Color(white: 0.1),
        subtext: Color(white: 0.1).opacity(0.5),
        sub: .white.opacity(0.94),
        symbol: Color(white: 0.15),
        shadow: .black.opacity(0.22)
    )

    static let glass = Theme(
        id: "glass", name: "Liquid Glass",
        backdrop: .glass(dark: true),
        disk: .black.opacity(0.18),
        stroke: .white.opacity(0.18),
        slice: .white.opacity(0.06),
        sliceHover: [Color.white.opacity(0.42), Color.white.opacity(0.22)],
        glow: .white.opacity(0.7),
        hub: .black.opacity(0.28),
        text: .white,
        subtext: .white.opacity(0.65),
        sub: .black.opacity(0.42),
        symbol: .white,
        shadow: .black.opacity(0.3)
    )

    static let all: [Theme] = [midnight, daylight, glass]

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? midnight
    }
}
