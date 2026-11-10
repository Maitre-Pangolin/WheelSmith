import Foundation
import Combine
import RingCore

/// Owns the config: loads ~/.config/theonering/config.json, saves edits made in Settings (debounced),
/// and live-reloads when the file is edited by hand.
final class ConfigStore: ObservableObject {
    @Published var config: RingConfig
    @Published private(set) var lastError: String?

    let url: URL
    private var lastWritten: Data?
    private var watcher: DispatchSourceFileSystemObject?
    private var cancellables: Set<AnyCancellable> = []

    init(url: URL = ConfigFile.defaultURL) {
        self.url = url
        config = DefaultConfig.config
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: url) {
            do {
                config = try ConfigFile.decode(data)
                lastWritten = data
            } catch {
                lastError = "config.json is invalid, using defaults: \(Self.describe(error))"
            }
        } else {
            write(config)
        }

        $config
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.write($0) }
            .store(in: &cancellables)

        startWatching()
    }

    func resetToDefaults() {
        config = DefaultConfig.config
    }

    private func write(_ config: RingConfig) {
        guard let data = try? ConfigFile.encode(config), data != lastWritten else { return }
        do {
            try data.write(to: url, options: .atomic)
            lastWritten = data
        } catch {
            lastError = "Could not save config: \(error.localizedDescription)"
        }
    }

    private func reloadFromDisk() {
        guard let data = try? Data(contentsOf: url), data != lastWritten else { return }
        do {
            let loaded = try ConfigFile.decode(data)
            lastWritten = data
            lastError = nil
            if !loaded.sameContent(as: config) { config = loaded }
        } catch {
            lastError = "config.json is invalid, keeping previous config: \(Self.describe(error))"
        }
    }

    /// Watches the directory (editors save atomically by renaming, which a file watch would miss).
    private func startWatching() {
        let dir = url.deletingLastPathComponent().path
        let fd = open(dir, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            // Let the editor finish its write/rename dance.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self?.reloadFromDisk() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let ctx): return ctx.debugDescription
        case DecodingError.keyNotFound(let key, let ctx):
            return "missing “\(key.stringValue)” at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case DecodingError.typeMismatch(_, let ctx), DecodingError.valueNotFound(_, let ctx):
            return "\(ctx.debugDescription) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        default: return error.localizedDescription
        }
    }
}
