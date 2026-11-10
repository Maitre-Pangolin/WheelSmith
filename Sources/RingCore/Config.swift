import Foundation

/// What a slice does when the hotkey is released over it.
public enum Action: Equatable, Sendable {
    /// Focus the app (launch it if needed). Behaves like clicking its Dock icon.
    case app(bundleId: String)
    /// Open a URL / file path, optionally with a specific app.
    case url(String, bundleId: String?)
    /// Send a keyboard shortcut, optionally focusing an app first. Needs Accessibility permission.
    case keys(String, bundleId: String?)
    /// Run a shell command with `/bin/zsh -lc`.
    case shell(String)
    /// Do nothing (useful for a slice that only groups sub-actions).
    case none

    public enum Kind: String, CaseIterable, Codable, Sendable {
        case app, url, keys, shell, none
    }

    public var kind: Kind {
        switch self {
        case .app: .app
        case .url: .url
        case .keys: .keys
        case .shell: .shell
        case .none: .none
        }
    }

    public var bundleId: String? {
        switch self {
        case .app(let b): b
        case .url(_, let b), .keys(_, let b): b
        case .shell, .none: nil
        }
    }

    /// The same action converted to another kind, keeping whatever carries over (the target app).
    public func converted(to kind: Kind) -> Action {
        if kind == self.kind { return self }
        switch kind {
        case .app: return .app(bundleId: bundleId ?? "")
        case .url: return .url("", bundleId: nil)
        case .keys: return .keys("", bundleId: bundleId)
        case .shell: return .shell("")
        case .none: return .none
        }
    }
}

extension Action: Codable {
    private enum CodingKeys: String, CodingKey { case type, bundleId, url, keys, command }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .app: self = .app(bundleId: try c.decode(String.self, forKey: .bundleId))
        case .url: self = .url(try c.decode(String.self, forKey: .url), bundleId: try c.decodeIfPresent(String.self, forKey: .bundleId))
        case .keys: self = .keys(try c.decode(String.self, forKey: .keys), bundleId: try c.decodeIfPresent(String.self, forKey: .bundleId))
        case .shell: self = .shell(try c.decode(String.self, forKey: .command))
        case .none: self = .none
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .type)
        switch self {
        case .app(let b): try c.encode(b, forKey: .bundleId)
        case .url(let u, let b): try c.encode(u, forKey: .url); try c.encodeIfPresent(b, forKey: .bundleId)
        case .keys(let k, let b): try c.encode(k, forKey: .keys); try c.encodeIfPresent(b, forKey: .bundleId)
        case .shell(let cmd): try c.encode(cmd, forKey: .command)
        case .none: break
        }
    }
}

/// One slice of the wheel (or one sub-action of a slice).
public struct WheelItem: Identifiable, Equatable, Sendable {
    /// Runtime identity only (not persisted).
    public var id = UUID()
    public var label: String
    /// nil = automatic (app icon or a symbol for the action type), "sf:<symbol name>", or an image file path.
    public var icon: String?
    public var action: Action
    public var children: [WheelItem]

    public init(label: String, icon: String? = nil, action: Action, children: [WheelItem] = []) {
        self.label = label
        self.icon = icon
        self.action = action
        self.children = children
    }
}

extension WheelItem: Codable {
    private enum CodingKeys: String, CodingKey { case label, icon, action, children }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        action = try c.decodeIfPresent(Action.self, forKey: .action) ?? .none
        children = try c.decodeIfPresent([WheelItem].self, forKey: .children) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(action, forKey: .action)
        if !children.isEmpty { try c.encode(children, forKey: .children) }
    }
}

public struct RingConfig: Equatable, Sendable {
    public static let maxItems = 8
    public static let maxChildren = 5

    /// e.g. "option+space". Hold it to show the wheel, release to run.
    public var hotkey: String
    /// Theme id, see `Theme.all` in the app.
    public var theme: String
    /// Slices, clockwise starting at the top.
    public var items: [WheelItem]

    public init(hotkey: String = "option+space", theme: String = "midnight", items: [WheelItem]) {
        self.hotkey = hotkey
        self.theme = theme
        self.items = items
    }

    /// Same content, ignoring runtime ids.
    public func sameContent(as other: RingConfig) -> Bool {
        (try? ConfigFile.encode(self)) == (try? ConfigFile.encode(other))
    }
}

extension RingConfig: Codable {
    private enum CodingKeys: String, CodingKey { case version, hotkey, theme, items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? "option+space"
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "midnight"
        let decoded = try c.decodeIfPresent([WheelItem].self, forKey: .items) ?? []
        items = Array(decoded.prefix(Self.maxItems)).map { item in
            var item = item
            item.children = Array(item.children.prefix(Self.maxChildren))
            return item
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(1, forKey: .version)
        try c.encode(hotkey, forKey: .hotkey)
        try c.encode(theme, forKey: .theme)
        try c.encode(items, forKey: .items)
    }
}

public enum ConfigFile {
    /// ~/.config/theonering/config.json, or $THEONERING_CONFIG when set (handy for development).
    public static var defaultURL: URL {
        if let override = ProcessInfo.processInfo.environment["THEONERING_CONFIG"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/theonering/config.json")
    }

    public static func encode(_ config: RingConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(config)
    }

    public static func decode(_ data: Data) throws -> RingConfig {
        try JSONDecoder().decode(RingConfig.self, from: data)
    }

    public static func decode(json: String) throws -> RingConfig {
        try decode(Data(json.utf8))
    }
}
