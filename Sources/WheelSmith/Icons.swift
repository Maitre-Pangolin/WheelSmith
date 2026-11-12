import AppKit
import SwiftUI
import RingCore

enum IconRef {
    case image(NSImage)
    case symbol(String)
}

/// Resolves and caches item icons so opening the wheel never touches the disk.
final class IconCache {
    static let shared = IconCache()
    private var images: [String: NSImage] = [:]

    func icon(for item: WheelItem, isChild: Bool = false) -> IconRef {
        if let spec = item.icon?.trimmingCharacters(in: .whitespaces), !spec.isEmpty {
            if spec.hasPrefix("sf:") { return .symbol(String(spec.dropFirst(3))) }
            if let img = image(atPath: (spec as NSString).expandingTildeInPath) { return .image(img) }
        }
        switch item.action {
        case .app(let bundleId):
            if let img = appIcon(bundleId) { return .image(img) }
        case .keys(_, let bundleId?) where !isChild, .url(_, let bundleId?) where !isChild,
             .menu(_, let bundleId?) where !isChild:
            if let img = appIcon(bundleId) { return .image(img) }
        default: break
        }
        return .symbol(Self.defaultSymbol(for: item.action.kind))
    }

    static func defaultSymbol(for kind: Action.Kind) -> String {
        switch kind {
        case .app: "app.dashed"
        case .url: "link"
        case .keys: "command"
        case .menu: "filemenu.and.selection"
        case .shell: "terminal"
        case .prompt: "text.cursor"
        case .none: "circle.dotted"
        }
    }

    func appIcon(_ bundleId: String) -> NSImage? {
        let key = "app:" + bundleId
        if let cached = images[key] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 128, height: 128)
        images[key] = img
        return img
    }

    private func image(atPath path: String) -> NSImage? {
        if let cached = images[path] { return cached }
        guard let img = NSImage(contentsOfFile: path) else { return nil }
        images[path] = img
        return img
    }

    /// Resolve everything up front (called on launch and whenever the config changes).
    func preload(_ items: [WheelItem]) {
        for item in items {
            _ = icon(for: item)
            item.children.forEach { _ = icon(for: $0, isChild: true) }
        }
    }
}

struct IconView: View {
    let icon: IconRef
    let size: CGFloat
    var tint: Color = .primary

    var body: some View {
        switch icon {
        case .image(let img):
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.6, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }
}
