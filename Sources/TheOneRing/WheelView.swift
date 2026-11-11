import SwiftUI
import AppKit
import RingCore

/// Live state shared between the controller (which tracks the cursor) and the SwiftUI view.
final class WheelModel: ObservableObject {
    @Published var items: [WheelItem] = []
    @Published var theme: Theme = .midnight
    @Published var hit: WheelHit = .center
    @Published var openParent: Int?
    @Published var visible = false
    /// Open windows per slice index (filled shortly after the wheel opens).
    @Published var windows: [Int: [WindowInfo]] = [:]
    /// Display the wheel is on, and how many there are (for the window badges).
    @Published var hereDisplay: Int?
    @Published var displayCount = 1
    /// Set by the snapshot renderer: draw a solid backdrop (blur can't be captured offscreen).
    var opaqueBackdrop = false
}

struct LiveWheelView: View {
    @ObservedObject var model: WheelModel

    var body: some View {
        WheelCanvas(items: model.items, theme: model.theme, hit: model.hit,
                    openParent: model.openParent, visible: model.visible,
                    opaqueBackdrop: model.opaqueBackdrop, windows: model.windows,
                    hereDisplay: model.hereDisplay, displayCount: model.displayCount)
    }
}

/// Stateless drawing of the wheel. Reused by the overlay and the Settings preview.
struct WheelCanvas: View {
    let items: [WheelItem]
    let theme: Theme
    let hit: WheelHit
    let openParent: Int?
    var visible = true
    var opaqueBackdrop = false
    var showsHubHint = true
    var windows: [Int: [WindowInfo]] = [:]
    var hereDisplay: Int?
    var displayCount = 1
    var metrics = WheelMetrics.standard

    private func ring(_ i: Int) -> Ring { Ring(item: items[i], windows: windows[i] ?? []) }
    private var geometry: WheelGeometry {
        WheelGeometry(childCounts: items.indices.map { ring($0).count }, metrics: metrics)
    }
    private var size: CGFloat { metrics.canvasSize }
    private var spring: Animation { .spring(response: 0.22, dampingFraction: 0.78) }

    var body: some View {
        ZStack {
            subRing
            disk
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                slice(index, item)
            }
            hub
        }
        .frame(width: size, height: size)
        .scaleEffect(visible ? 1 : 0.82)
        .opacity(visible ? 1 : 0)
        .animation(.spring(response: 0.24, dampingFraction: 0.8), value: visible)
        .animation(spring, value: hit)
        .animation(spring, value: openParent)
    }

    // MARK: Disk

    private var disk: some View {
        let d = metrics.ringOuter * 2
        return ZStack {
            Backdrop(theme: theme, opaque: opaqueBackdrop, shape: Circle())
            Circle().fill(theme.disk)
            Circle().strokeBorder(theme.stroke, lineWidth: 1)
        }
        .frame(width: d, height: d)
        .shadow(color: theme.shadow, radius: 30, y: 12)
    }

    // MARK: Slices

    @ViewBuilder
    private func slice(_ i: Int, _ item: WheelItem) -> some View {
        let center = geometry.sliceCenter(i)
        let span = geometry.sliceSpan
        let selected = hit == .item(i)
        let parentOfSelected = { if case .child(i, _) = hit { return true } else { return false } }()
        let active = selected || parentOfSelected
        let dimmed = hit.itemIndex != nil && !active
        let midRadius = (metrics.ringInner + metrics.ringOuter) / 2
        let iconSize: CGFloat = items.count > 6 ? 40 : 46

        ZStack {
            AnnularSector(center: center, span: items.count == 1 ? 2 * .pi : span,
                          inner: metrics.ringInner,
                          outer: selected ? metrics.ringOuter + 6 : metrics.ringOuter - 6)
                .fill(active ? AnyShapeStyle(LinearGradient(colors: theme.sliceHover,
                                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                             : AnyShapeStyle(theme.slice))
                .opacity(parentOfSelected ? 0.55 : 1)
                .shadow(color: selected ? theme.glow.opacity(0.65) : .clear, radius: 16)

            IconView(icon: IconCache.shared.icon(for: item), size: iconSize, tint: theme.symbol)
                .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.12), radius: 4, y: 2)
                .scaleEffect(selected ? 1.16 : 1)
                .opacity(dimmed ? 0.55 : 1)
                .position(Self.point(center, midRadius + (selected ? 4 : 0), size))

            if ring(i).count > 0 {
                // Small dot on the rim hinting there are sub-actions or windows.
                Circle()
                    .fill(active ? theme.text : theme.subtext)
                    .frame(width: 4, height: 4)
                    .position(Self.point(center, metrics.ringOuter - 12, size))
                    .opacity(selected ? 0 : 1)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: Sub-actions

    @ViewBuilder
    private var subRing: some View {
        if let p = openParent, p < items.count, ring(p).count > 0 {
            let entries = ring(p).entries
            let angles = geometry.childAngles(parent: p)
            let mid = (metrics.subInner + metrics.subOuter) / 2
            ZStack {
                ForEach(Array(entries.enumerated()), id: \.element.id) { j, entry in
                    let selected = hit == .child(p, j)
                    ZStack {
                        AnnularSector(center: angles[j], span: metrics.childSpan, inner: metrics.subInner,
                                      outer: selected ? metrics.subOuter + 6 : metrics.subOuter)
                            .fill(selected ? AnyShapeStyle(LinearGradient(colors: theme.sliceHover,
                                                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                                           : AnyShapeStyle(theme.sub))
                            .overlay(
                                AnnularSector(center: angles[j], span: metrics.childSpan, inner: metrics.subInner,
                                              outer: selected ? metrics.subOuter + 6 : metrics.subOuter)
                                    .stroke(theme.stroke, lineWidth: 1)
                            )
                            .shadow(color: selected ? theme.glow.opacity(0.6) : theme.shadow.opacity(0.5),
                                    radius: selected ? 14 : 8)
                        ringEntryLabel(entry, selected: selected)
                        .scaleEffect(selected ? 1.08 : 1)
                        .position(Self.point(angles[j], mid + (selected ? 3 : 0), size))
                    }
                }
            }
            .frame(width: size, height: size)
            .transition(.scale(scale: 0.86).combined(with: .opacity))
            .id(p)
        }
    }

    // MARK: Hub

    private var hub: some View {
        let d = metrics.hubRadius * 2
        let onCenter = hit == .center
        return ZStack {
            Circle()
                .fill(onCenter ? theme.hubHover : theme.hub)
                .overlay(Circle().strokeBorder(onCenter ? AnyShapeStyle(LinearGradient(colors: theme.sliceHover, startPoint: .top, endPoint: .bottom))
                                                        : AnyShapeStyle(theme.stroke), lineWidth: onCenter ? 1.5 : 1))
            hubContent
                .padding(8)
                .frame(width: d, height: d)
        }
        .frame(width: d, height: d)
    }

    @ViewBuilder
    private var hubContent: some View {
        switch hit {
        case .center:
            if showsHubHint {
                VStack(spacing: 2) {
                    Image(systemName: "gearshape.fill").font(.system(size: 15, weight: .semibold))
                    Text("Settings").font(.system(size: 9, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(theme.subtext)
            }
        case .item(let i) where i < items.count:
            hubLabel(items[i].label, caption: nil)
        case .child(let p, let j) where p < items.count && j < ring(p).count:
            switch ring(p).entries[j] {
            case .window(let w): hubLabel(w.title, caption: windowCaption(w, app: items[p].label))
            case .action(let a): hubLabel(a.label, caption: items[p].label)
            }
        case .cancel:
            VStack(spacing: 2) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                Text("Cancel").font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(theme.subtext)
        default:
            EmptyView()
        }
    }

    // MARK: Ring entries

    @ViewBuilder
    private func ringEntryLabel(_ entry: Ring.Entry, selected: Bool) -> some View {
        VStack(spacing: 4) {
            switch entry {
            case .action(let child):
                IconView(icon: IconCache.shared.icon(for: child, isChild: true), size: 22,
                         tint: selected ? .white : theme.symbol)
            case .window(let w):
                ZStack(alignment: .topTrailing) {
                    Image(systemName: w.isMinimized ? "minus.rectangle" : "macwindow")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? .white : theme.symbol)
                        .frame(width: 26, height: 22)
                    if displayCount > 1, let d = w.displayIndex {
                        let here = d == hereDisplay
                        Text("\(d + 1)")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundStyle(here ? Color.white : theme.text)
                            .frame(width: 12, height: 12)
                            .background(Circle().fill(here ? AnyShapeStyle(LinearGradient(colors: theme.sliceHover, startPoint: .top, endPoint: .bottom))
                                                           : AnyShapeStyle(theme.stroke.opacity(2))))
                            .offset(x: 6, y: -5)
                    }
                }
            }
            Text(entry.label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? .white : theme.subtext)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 92)
                .opacity(entry.isDimmed && !selected ? 0.6 : 1)
        }
    }

    private func windowCaption(_ w: WindowInfo, app: String) -> String {
        guard displayCount > 1, let d = w.displayIndex else { return app }
        return d == hereDisplay ? "\(app) · this display" : "\(app) · display \(d + 1)"
    }

    private func hubLabel(_ title: String, caption: String?) -> some View {
        VStack(spacing: 1) {
            if let caption {
                Text(caption)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.subtext)
                    .lineLimit(1)
            }
            Text(title)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .id(title)
        .transition(.opacity)
    }

    /// Position for angle θ (0 = up, clockwise) at radius r, in a square canvas of side `size`.
    static func point(_ angle: Double, _ r: Double, _ size: CGFloat) -> CGPoint {
        CGPoint(x: size / 2 + r * sin(angle), y: size / 2 - r * cos(angle))
    }
}

// MARK: - Ring model

/// What a slice's outer ring shows: its open windows (only when it has 2+), then its sub-actions.
/// Shared by the drawing and the controller so indices always line up.
struct Ring {
    enum Entry: Identifiable {
        case window(WindowInfo)
        case action(WheelItem)

        var id: UUID {
            switch self {
            case .window(let w): w.id
            case .action(let a): a.id
            }
        }
        var label: String {
            switch self {
            case .window(let w): w.title
            case .action(let a): a.label
            }
        }
        var isDimmed: Bool { if case .window(let w) = self { w.isMinimized } else { false } }
    }

    let entries: [Entry]
    var count: Int { entries.count }

    init(item: WheelItem, windows: [WindowInfo]) {
        let shown = RingLayout.counts(windows: windows.count, actions: item.children.count)
        entries = windows.prefix(shown.windows).map(Entry.window) + item.children.prefix(shown.actions).map(Entry.action)
    }
}

// MARK: - Shapes & backdrop

/// A ring segment. Angles use the wheel convention (0 = up, clockwise); `gap` is a constant-width
/// gutter in points between neighbouring segments.
struct AnnularSector: Shape {
    var center: Double
    var span: Double
    var inner: Double
    var outer: Double
    var gap: Double = 4

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(inner, outer) }
        set { inner = newValue.first; outer = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        if span >= 2 * .pi - 0.001 {
            p.addEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
            p.addEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
            return p.normalized(eoFill: true)
        }
        // Wheel angle → SwiftUI angle (0 = +x axis; increasing angles run clockwise on screen).
        let toSwiftUI = { (a: Double) in Angle.radians(a - .pi / 2) }
        let a0 = center - span / 2, a1 = center + span / 2
        let gOuter = asin(min(1, gap / 2 / outer)), gInner = asin(min(1, gap / 2 / inner))
        p.addArc(center: c, radius: outer, startAngle: toSwiftUI(a0 + gOuter), endAngle: toSwiftUI(a1 - gOuter), clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: toSwiftUI(a1 - gInner), endAngle: toSwiftUI(a0 + gInner), clockwise: true)
        p.closeSubpath()
        return p
    }
}

private extension Path {
    func normalized(eoFill: Bool) -> Path {
        eoFill ? Path(cgPath.normalized(using: .evenOdd)) : self
    }
}

struct Backdrop<S: Shape>: View {
    let theme: Theme
    var opaque = false
    let shape: S

    var body: some View {
        if opaque {
            shape.fill(theme.isDark ? Color(white: 0.1) : Color(white: 0.93))
        } else {
            switch theme.backdrop {
            case .blur(let material, let dark):
                BlurView(material: material, dark: dark).clipShape(shape)
            case .glass(let dark):
                if #available(macOS 26.0, *) {
                    Color.clear
                        .glassEffect(.regular, in: shape)
                        .environment(\.colorScheme, dark ? .dark : .light)
                } else {
                    BlurView(material: .hudWindow, dark: dark).clipShape(shape)
                }
            }
        }
    }
}

/// Behind-window blur, masked to a circle with `maskImage` (the supported way to shape it).
struct BlurView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let dark: Bool

    func makeNSView(context: Context) -> CircularEffectView {
        let v = CircularEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: CircularEffectView, context: Context) {
        v.material = material
        v.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    final class CircularEffectView: NSVisualEffectView {
        private var maskedSize: NSSize = .zero
        override func layout() {
            super.layout()
            guard bounds.size != maskedSize, bounds.width > 0 else { return }
            maskedSize = bounds.size
            maskImage = NSImage(size: bounds.size, flipped: false) { rect in
                NSColor.black.setFill()
                NSBezierPath(ovalIn: rect).fill()
                return true
            }
        }
    }
}
