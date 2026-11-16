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
    /// The wheel has been open long enough that letting go in the center opens Settings.
    @Published var settingsArmed = false
    /// Open windows per slice index (filled shortly after the wheel opens).
    @Published var windows: [Int: [WindowInfo]] = [:]
    /// Display the wheel is on, and how many there are (for the window badges).
    @Published var hereDisplay: Int?
    @Published var displayCount = 1
    /// Set while a Prompt action waits for text: the wheel stays open with a text field beside it.
    @Published var prompt: PromptModel?
    /// Horizontal offset of the text field's center from the wheel's center (negative: on the left).
    @Published var promptOffset: CGFloat = 0
    /// Shown in the hub for a moment after switching themes with the arrow keys.
    @Published var themeToast: ThemeToast?
    /// Set by the snapshot renderer: draw a solid backdrop (blur can't be captured offscreen).
    var opaqueBackdrop = false
}

/// The theme just picked with the arrow keys: its name, and which one of how many.
struct ThemeToast: Equatable {
    let name: String
    let detail: String
}

/// The wheel, centered, with room on either side for a prompt's text field.
enum Stage {
    /// Between the wheel (or its open sub-actions) and the text field.
    static let promptGap: CGFloat = 18
    /// Half the text field's height with a status line, used to keep it clear of the sub-actions.
    static let promptHalfHeight: Double = 62

    static func size(_ m: WheelMetrics = .standard) -> CGSize {
        let half = max(CGFloat(m.canvasSize) / 2, CGFloat(m.subOuter) + promptGap + PromptCard.width + 12)
        return CGSize(width: 2 * half, height: m.canvasSize)
    }
}

struct LiveWheelView: View {
    @ObservedObject var model: WheelModel

    var body: some View {
        ZStack {
            WheelCanvas(items: model.items, theme: model.theme, hit: model.hit,
                        openParent: model.openParent, visible: model.visible,
                        opaqueBackdrop: model.opaqueBackdrop, windows: model.windows,
                        hereDisplay: model.hereDisplay, displayCount: model.displayCount,
                        dimmed: model.prompt != nil, settingsArmed: model.settingsArmed,
                        themeToast: model.themeToast)
            if let prompt = model.prompt {
                PromptCard(model: prompt, opaqueBackdrop: model.opaqueBackdrop)
                    .offset(x: model.promptOffset)
                    .opacity(model.visible ? 1 : 0)
                    .transition(.opacity.combined(with: .offset(x: model.promptOffset < 0 ? 14 : -14)))
            }
        }
        .frame(width: Stage.size().width, height: Stage.size().height)
        .animation(.spring(response: 0.24, dampingFraction: 0.8), value: model.prompt != nil)
    }
}

/// Stateless drawing of the wheel (apart from where the rails last pointed). Reused by the overlay,
/// the Settings preview and the snapshot renderer.
///
/// Layout, from the center out: hub, inner rail, slice wedges with their icons, outer rail,
/// sub-action wedges, sub-action rail. The hovered slice gets a quiet fill; the rails carry the
/// selection and turn to follow the pointer.
struct WheelCanvas: View {
    let items: [WheelItem]
    let theme: Theme
    let hit: WheelHit
    let openParent: Int?
    var visible = true
    var opaqueBackdrop = false
    var windows: [Int: [WindowInfo]] = [:]
    var hereDisplay: Int?
    var displayCount = 1
    /// Recedes behind a prompt's text field.
    var dimmed = false
    /// Letting go in the center opens Settings (after the wheel has been open a moment).
    var settingsArmed = false
    /// How much of the Settings arm ring to draw, for still renders; nil fills it over a second after opening.
    var armProgress: Double? = nil
    /// Overrides the hub's content right after an arrow key switched the theme.
    var themeToast: ThemeToast? = nil
    var metrics = WheelMetrics.standard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Unwrapped rail angles, so a rail always turns the short way round. Nil until the first hover.
    @State private var innerAngle: Double?
    @State private var outerAngle: Double?

    private func ring(_ i: Int) -> Ring { Ring(item: items[i], windows: windows[i] ?? []) }
    private var geometry: WheelGeometry {
        WheelGeometry(childCounts: items.indices.map { ring($0).count }, metrics: metrics)
    }
    private var size: CGFloat { metrics.canvasSize }
    private var focus: Int? { hit.itemIndex.flatMap { $0 < items.count ? $0 : nil } }
    private var onChild: Bool { if case .child = hit { true } else { false } }
    /// Icons sit a little inside the middle of the wedge band.
    private var tileRadius: Double { (metrics.ringInner + metrics.ringOuter) / 2 - 3 }

    // MARK: Motion

    /// Rails turn with one small overshoot, then settle.
    private var railTurn: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.75) }
    /// Rails change length and radius without overshoot.
    private var railResize: Animation? { reduceMotion ? nil : .smooth(duration: 0.38) }
    private var fade: Animation { .easeOut(duration: 0.16) }
    /// Looping theme effects (rail flicker, disk spin) run only while the live wheel is open.
    private var idleActive: Bool { visible && !reduceMotion && !opaqueBackdrop }

    private var spec: ThemeSpec { theme.spec }
    private var center: CGFloat { size / 2 }
    /// The design's 720 pt wheel area: wedge and sub-action paints span it and are clipped to their wedge.
    private var paintBox: CGRect {
        let b = ThemeContrast.paintBox
        return CGRect(x: center - b / 2, y: center - b / 2, width: b, height: b)
    }
    private func circle(_ r: Double) -> CGRect { CGRect(x: center - r, y: center - r, width: 2 * r, height: 2 * r) }

    var body: some View {
        ZStack {
            disk
            halo
            wedges
            innerRail
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                tile(index, item)
            }
            subActions
            outerRails
            armRing
            hub
        }
        .opacity(dimmed ? 0.55 : 1)
        .frame(width: size, height: size)
        .scaleEffect(visible || reduceMotion ? 1 : 0.95)
        .opacity(visible ? 1 : 0)
        .animation(visible ? .spring(response: 0.28, dampingFraction: 0.72) : .easeOut(duration: 0.1), value: visible)
        .animation(.easeOut(duration: 0.15), value: openParent)
        .onChange(of: hit) { old, new in turnRails(from: old, to: new) }
        .onChange(of: visible) { _, now in
            if !now { innerAngle = nil; outerAngle = nil }
        }
    }

    // MARK: Rails

    /// Where the inner and outer rails point for a hit, if they're shown at all.
    private func railTargets(_ hit: WheelHit) -> (inner: Double, outer: Double)? {
        switch hit {
        case .item(let i) where i < items.count:
            let c = geometry.sliceCenter(i)
            return (c, c)
        case .child(let p, let j) where p < items.count:
            let angles = geometry.childAngles(parent: p)
            guard j < angles.count else { return nil }
            return (geometry.sliceCenter(p), angles[j])
        default:
            return nil
        }
    }

    private func turnRails(from old: WheelHit, to new: WheelHit) {
        guard let target = railTargets(new) else { return } // hidden rails stay where they were
        let previous = railTargets(old)
        innerAngle = Self.unwrap(target.inner, near: innerAngle ?? previous?.inner ?? target.inner)
        outerAngle = Self.unwrap(target.outer, near: outerAngle ?? previous?.outer ?? target.outer)
    }

    private var railStroke: StrokeStyle { spec.rail.strokeStyle }

    /// A rail arc of `radius` and `span`, centered on straight up, in the rail colors and glow.
    private func rail(_ radius: Double, span: Double) -> some View {
        let half = radius * sin(min(span, .pi) / 2)
        return RailArc(radius: radius, span: span)
            .stroke(spec.rail.shading(minX: center - half, maxX: center + half, width: size), style: railStroke)
            .shadows(spec.rail.glow)
    }

    /// Under the hovered slice, just outside the hub. Hidden while a sub-action is hovered.
    private var innerRail: some View {
        let angle = innerAngle ?? railTargets(hit)?.inner ?? 0
        return rail(metrics.innerRail, span: max(geometry.sliceSpan - 0.24, 0.1))
            .idle(spec.rail.idle, active: idleActive)
            .frame(width: size, height: size)
            .rotationEffect(.radians(angle))
            .animation(railTurn, value: angle)
            .opacity(focus != nil && !onChild ? 1 : 0)
            .animation(fade, value: focus != nil && !onChild)
    }

    /// Outside the hovered slice. On a sub-action it narrows and moves inside it, and a third rail
    /// grows out beyond the sub-action.
    private var outerRails: some View {
        let angle = outerAngle ?? railTargets(hit)?.outer ?? 0
        let span = onChild ? metrics.childSpan - 0.08 : max(geometry.sliceSpan - 0.1, 0.1)
        return ZStack {
            rail(metrics.outerRail, span: span)
                .animation(railResize, value: span)
            rail(metrics.subRail, span: metrics.childSpan - 0.08)
                .frame(width: size, height: size)
                .scaleEffect(onChild ? 1 : metrics.outerRail / metrics.subRail)
                .opacity(onChild ? 1 : 0)
                .animation(railResize ?? fade, value: onChild)
        }
        .idle(spec.rail.idle, active: idleActive)
        .frame(width: size, height: size)
        .rotationEffect(.radians(angle))
        .animation(railTurn, value: angle)
        .opacity(focus != nil ? 1 : 0)
        .animation(fade, value: focus != nil)
    }

    /// How far the Settings arm ring has filled: animated over `settingsDelay` from opening, or fixed for still renders.
    private var armTarget: Double { armProgress ?? (settingsArmed ? 1 : (!reduceMotion && visible ? 1 : 0)) }
    private var armFill: Animation? {
        armProgress == nil && !reduceMotion && visible ? .linear(duration: WheelController.settingsDelay) : nil
    }

    /// Fills around the hub, like a loading bar, over the first two seconds; once full it pulses, and
    /// letting go in the center opens Settings.
    private var armRing: some View {
        Circle()
            .trim(from: 0, to: armTarget)
            .stroke(Color(spec.rail.colors.first ?? .white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .shadows(spec.rail.glow)
            .rotationEffect(.degrees(-90))
            .frame(width: metrics.innerRail * 2, height: metrics.innerRail * 2)
            .animation(armFill, value: visible)
            .animation(reduceMotion ? fade : nil, value: settingsArmed)
            // Done: a short pulse.
            .keyframeAnimator(initialValue: 1.0, trigger: settingsArmed) { ring, scale in
                ring.scaleEffect(reduceMotion || !settingsArmed ? 1 : scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.08, duration: 0.12)
                    SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
                }
            }
            .opacity(hit == .center ? 1 : 0)
            .animation(fade, value: hit == .center)
    }

    // MARK: Disk & wedges


    private var disk: some View {
        let r = circle(metrics.diskRadius)
        return ZStack {
            OuterShadows(shadows: spec.diskEdge.shadows ?? [], circle: r)
            Backdrop(theme: theme, opaque: opaqueBackdrop, shape: Circle())
                .frame(width: r.width, height: r.height)
            PaintView(paint: spec.disk, box: r, clip: Path(ellipseIn: r))
                .spin(spec.diskIdle, active: idleActive)
            InnerEdge(edge: spec.diskEdge, circle: r)
        }
        .frame(width: size, height: size)
    }

    /// A soft glow under the hovered slice, turning with the inner rail.
    @ViewBuilder
    private var halo: some View {
        if let halo = spec.halo {
            let angle = innerAngle ?? railTargets(hit)?.inner ?? 0
            Circle()
                .fill(Color(halo))
                .frame(width: 180, height: 180)
                .blur(radius: 30)
                .offset(y: -150)
                .frame(width: size, height: size)
                .rotationEffect(.radians(angle))
                .animation(railTurn, value: angle)
                .opacity(focus != nil && !onChild ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: focus != nil && !onChild)
        }
    }

    private func wedgePath(_ i: Int) -> Path {
        AnnularSector(center: geometry.sliceCenter(i), span: items.count == 1 ? 2 * .pi : geometry.sliceSpan,
                      inner: metrics.ringInner, outer: metrics.ringOuter)
            .path(in: CGRect(x: 0, y: 0, width: size, height: size))
    }

    private var wedges: some View {
        ZStack {
            ForEach(items.indices, id: \.self) { i in
                let path = wedgePath(i)
                PaintView(paint: spec.slice, box: paintBox, clip: path)
                PaintView(paint: spec.sliceHover, box: paintBox, clip: path)
                    .opacity(focus == i ? 1 : 0)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.14), value: focus)
    }

    /// A slice's icon. Pops in with a short stagger when the wheel opens; grows a little when hovered
    /// while the others dim.
    private func tile(_ i: Int, _ item: WheelItem) -> some View {
        let selected = focus == i
        let pop: Animation? = visible && !reduceMotion
            ? .spring(response: 0.34, dampingFraction: 0.62).delay(0.04 + Double(i) * 0.022) : nil
        return IconView(icon: IconCache.shared.icon(for: item), size: 36, tint: theme.symbol)
            .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.12), radius: 3, y: 1.5)
            .scaleEffect(selected ? 1.12 : 1)
            .opacity(focus != nil && !selected ? 0.55 : 1)
            .animation(reduceMotion ? fade : .spring(response: 0.3, dampingFraction: 0.6), value: selected)
            .animation(fade, value: focus != nil)
            .scaleEffect(visible || reduceMotion ? 1 : 0.6)
            .opacity(visible ? 1 : 0)
            .animation(pop, value: visible)
            .position(Self.point(geometry.sliceCenter(i), tileRadius, size))
    }

    // MARK: Sub-actions

    private struct SubEntry: Identifiable {
        let parent: Int
        let index: Int
        let entry: Ring.Entry
        let angle: Double
        /// Changes with the parent, so a new set unfolds instead of morphing the old one.
        var id: String { "\(parent)-\(entry.id)" }
    }

    private var subEntries: [SubEntry] {
        guard let p = openParent, p < items.count else { return [] }
        let angles = geometry.childAngles(parent: p)
        return ring(p).entries.enumerated().map { SubEntry(parent: p, index: $0.offset, entry: $0.element, angle: angles[$0.offset]) }
    }

    private var subActions: some View {
        ZStack {
            ForEach(subEntries) { sub in
                subWedge(sub)
                    .transition(.asymmetric(
                        insertion: reduceMotion
                            ? .opacity.animation(fade)
                            : .scale(scale: 0.82).combined(with: .opacity)
                                .animation(.spring(response: 0.36, dampingFraction: 0.7).delay(Double(sub.index) * 0.045)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))))
            }
        }
        .frame(width: size, height: size)
    }

    private func subWedge(_ sub: SubEntry) -> some View {
        let selected = hit == .child(sub.parent, sub.index)
        let shape = AnnularSector(center: sub.angle, span: metrics.childSpan,
                                  inner: metrics.subInner, outer: metrics.subOuter, gap: 5)
        let path = shape.path(in: CGRect(x: 0, y: 0, width: size, height: size))
        return ZStack {
            PaintView(paint: spec.sub, box: paintBox, clip: path)
            PaintView(paint: spec.subHover, box: paintBox, clip: path)
                .opacity(selected ? 1 : 0)
            ringEntryLabel(sub.entry, selected: selected)
                .position(Self.point(sub.angle, (metrics.subInner + metrics.subOuter) / 2, size))
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.13), value: selected)
    }

    // MARK: Hub

    private var hub: some View {
        let d = metrics.hubRadius * 2
        // Letting go in the center closes the wheel, unless it has been open long enough to arm Settings.
        let onSettings = settingsArmed && hit == .center
        let r = circle(metrics.hubRadius)
        return ZStack {
            OuterShadows(shadows: spec.hubEdge.shadows ?? [], circle: r)
            PaintView(paint: spec.hub, box: r, clip: Path(ellipseIn: r))
            PaintView(paint: spec.hubHover, box: r, clip: Path(ellipseIn: r))
                .opacity(onSettings ? 1 : 0)
            InnerEdge(edge: spec.hubEdge, circle: r)
            hubContent
                .padding(12)
                .frame(width: d, height: d)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.18), value: onSettings)
        .animation(.easeOut(duration: 0.12), value: hit)
        .animation(.easeOut(duration: 0.12), value: themeToast)
    }

    @ViewBuilder
    private var hubContent: some View {
        if let themeToast {
            VStack(spacing: 2) {
                Text(themeToast.detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.subtext)
                hubLabel(themeToast.name, caption: nil)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                    Image(systemName: "arrow.up.arrow.down")
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.subtext)
                .padding(.top, 2)
            }
            .transition(.opacity)
        } else {
            hitContent
        }
    }

    @ViewBuilder
    private var hitContent: some View {
        switch hit {
        case .center:
            if settingsArmed {
                VStack(spacing: 4) {
                    Image(systemName: "gearshape").font(.system(size: 17, weight: .medium))
                    Text("Settings").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(theme.text)
                .transition(.asymmetric(insertion: .scale(scale: 0.7).combined(with: .opacity), removal: .opacity))
            } else {
                // Loading: a faint gear turns and brightens as the ring fills.
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(theme.subtext)
                    .rotationEffect(.degrees(reduceMotion ? 0 : armTarget * 120))
                    .opacity(0.15 + 0.45 * armTarget)
                    .animation(armFill, value: visible)
                    .transition(.opacity)
            }
        case .item(let i) where i < items.count:
            hubLabel(items[i].label, caption: nil)
        case .child(let p, let j) where p < items.count && j < ring(p).count:
            switch ring(p).entries[j] {
            case .window(let w): hubLabel(w.title, caption: windowCaption(w, app: items[p].label))
            case .action(let a): hubLabel(a.label, caption: items[p].label)
            }
        case .cancel:
            Text("Cancel")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.subtext)
        default:
            EmptyView()
        }
    }

    // MARK: Ring entries

    @ViewBuilder
    private func ringEntryLabel(_ entry: Ring.Entry, selected: Bool) -> some View {
        VStack(spacing: 5) {
            switch entry {
            case .action(let child):
                IconView(icon: IconCache.shared.icon(for: child, isChild: true), size: 24,
                         tint: selected ? theme.onHover : theme.symbol)
            case .window(let w):
                ZStack(alignment: .topTrailing) {
                    Image(systemName: w.isMinimized ? "minus.rectangle" : w.isFullScreen ? "arrow.up.left.and.arrow.down.right.square" : "macwindow")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(selected ? theme.onHover : theme.symbol)
                        .frame(width: 30, height: 24)
                    if displayCount > 1, let d = w.displayIndex {
                        let here = d == hereDisplay
                        Text("\(d + 1)")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundStyle(here ? theme.onHover : theme.text)
                            .frame(width: 12, height: 12)
                            .background(Circle().fill(here ? AnyShapeStyle(LinearGradient(colors: theme.subHover, startPoint: .top, endPoint: .bottom))
                                                           : AnyShapeStyle(theme.stroke.opacity(2))))
                            .offset(x: 6, y: -5)
                    }
                }
            }
            // Sub-actions are 1.5× the design's depth: their labels grow a little with them.
            let font = ThemeFont(spec.labelFont, defaultSize: 11, defaultWeight: .medium, scale: 1.12)
            Text(entry.label, themed: font)
                .font(font.font)
                .tracking(font.tracking)
                .foregroundStyle(selected ? theme.onHover : theme.symbol)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 116)
                .opacity(entry.isDimmed && !selected ? 0.6 : 1)
        }
    }

    private func windowCaption(_ w: WindowInfo, app: String) -> String {
        guard displayCount > 1, let d = w.displayIndex else { return app }
        return d == hereDisplay ? "\(app) · this display" : "\(app) · display \(d + 1)"
    }

    private func hubLabel(_ title: String, caption: String?) -> some View {
        VStack(spacing: 2) {
            if let caption {
                Text(caption)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.subtext)
                    .lineLimit(1)
            }
            let font = ThemeFont(spec.hubFont, defaultSize: 15, defaultWeight: .medium)
            Text(title, themed: font)
                .font(font.font)
                .tracking(spec.hubFont == nil ? -0.15 : font.tracking)
                .foregroundStyle(theme.text)
                .shadows(font.shadows)
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

    /// `angle` shifted by whole turns to within half a turn of `previous`.
    static func unwrap(_ angle: Double, near previous: Double) -> Double {
        var a = angle
        while a - previous > .pi { a -= 2 * .pi }
        while a - previous < -.pi { a += 2 * .pi }
        return a
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

/// An arc of a circle centered on the canvas, centered on straight up; rotate it into place.
/// `span` animates, so a rail can grow or shrink smoothly.
struct RailArc: Shape {
    var radius: Double
    var span: Double

    var animatableData: Double {
        get { span }
        set { span = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: c, radius: radius, startAngle: .radians(-span / 2 - .pi / 2),
                 endAngle: .radians(span / 2 - .pi / 2), clockwise: false)
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
    /// Rounded-rectangle mask for the blur; nil masks it to a circle.
    var cornerRadius: CGFloat? = nil

    var body: some View {
        if opaque {
            shape.fill(theme.isDark ? Color(white: 0.1) : Color(white: 0.93))
        } else {
            BlurView(material: theme.material, dark: theme.isDark, cornerRadius: cornerRadius).clipShape(shape)
        }
    }
}

/// Behind-window blur, masked to a circle (or a rounded rectangle) with `maskImage`, the supported way to shape it.
struct BlurView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let dark: Bool
    var cornerRadius: CGFloat? = nil

    func makeNSView(context: Context) -> CircularEffectView {
        let v = CircularEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: CircularEffectView, context: Context) {
        v.material = material
        v.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        v.cornerRadius = cornerRadius
    }

    final class CircularEffectView: NSVisualEffectView {
        private var maskedSize: NSSize = .zero
        var cornerRadius: CGFloat? {
            didSet { if cornerRadius != oldValue { maskedSize = .zero; needsLayout = true } }
        }

        override func layout() {
            super.layout()
            guard bounds.size != maskedSize, bounds.width > 0 else { return }
            maskedSize = bounds.size
            if let r = cornerRadius {
                // Stretchable: only the corners are drawn, the middle scales with the view.
                let image = NSImage(size: NSSize(width: 2 * r + 1, height: 2 * r + 1), flipped: false) { rect in
                    NSColor.black.setFill()
                    NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
                    return true
                }
                image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
                image.resizingMode = .stretch
                maskImage = image
                return
            }
            maskImage = NSImage(size: bounds.size, flipped: false) { rect in
                NSColor.black.setFill()
                NSBezierPath(ovalIn: rect).fill()
                return true
            }
        }
    }
}
