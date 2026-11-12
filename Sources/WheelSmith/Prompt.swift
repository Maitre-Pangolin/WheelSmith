import AppKit
import SwiftUI
import RingCore

/// State of a `.prompt` action while the wheel waits for text (see `WheelController.beginPrompt`).
final class PromptModel: ObservableObject {
    enum Status: Equatable {
        case editing
        case running
        case done(String)
        case failed(String)
    }

    @Published var text = ""
    @Published var status: Status = .editing
    var title = ""
    /// The parent slice's label, e.g. "Ostraka" for Ostraka › Quick todo.
    var caption: String?
    var placeholder = ""
    var icon: IconRef = .symbol("text.cursor")
    var theme = Theme.midnight
    var onSubmit: () -> Void = {}

    init(title: String = "", caption: String? = nil, placeholder: String? = nil, theme: Theme = .midnight) {
        self.title = title
        self.caption = caption
        self.placeholder = placeholder?.isEmpty == false ? placeholder! : "Type, then press Return"
        self.theme = theme
    }
}

enum PromptRunner {
    /// `/bin/zsh -lc <command> wheelsmith <argument>`: the text is `$1`, so it's never parsed as shell code.
    /// Calls back on the main thread with the non-empty output lines (stdout and stderr together).
    static func run(_ command: String, argument: String, completion: @escaping (Bool, [String]) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command, "wheelsmith", argument]
        process.environment = ActionRunner.shellEnvironment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("WheelSmith: prompt command failed to start: \(error)")
            completion(false, ["Couldn't run /bin/zsh"])
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let lines = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let ok = process.terminationStatus == 0
            if !ok { NSLog("WheelSmith: prompt command exited \(process.terminationStatus): \(lines.joined(separator: " | "))") }
            DispatchQueue.main.async { completion(ok, lines) }
        }
    }
}

/// The text field card laid over the middle of the wheel.
struct PromptCard: View {
    static let width: CGFloat = 440

    @ObservedObject var model: PromptModel
    /// For snapshots: behind-window blur can't be captured off-screen.
    var opaqueBackdrop = false
    @FocusState private var focused: Bool

    private var theme: Theme { model.theme }
    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                IconView(icon: model.icon, size: 15, tint: theme.symbol)
                    .frame(width: 18, height: 18)
                Text(heading)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.subtext)
                    .lineLimit(1)
                Spacer()
                Text("↩ send   esc quit")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(theme.subtext.opacity(0.8))
            }
            TextField("", text: $model.text, prompt: Text(model.placeholder).foregroundStyle(theme.subtext.opacity(0.7)))
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .foregroundStyle(theme.text)
                .focused($focused)
                .disabled(model.status == .running)
                .onSubmit { model.onSubmit() }
                .onChange(of: model.text) {
                    if case .failed = model.status { model.status = .editing }
                }
            statusLine
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: Self.width, alignment: .leading)
        .background { Backdrop(theme: theme, opaque: opaqueBackdrop, shape: shape, cornerRadius: 18) }
        .background(shape.fill(theme.hub))
        .overlay(shape.strokeBorder(theme.stroke, lineWidth: 1))
        .clipShape(shape)
        .shadow(color: theme.shadow, radius: 24, y: 10)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .onAppear { focused = true }
        .onChange(of: model.status) {
            // The field loses focus while disabled; take it back so you can fix the text after a failure.
            if model.status != .running { focused = true }
        }
    }

    private var heading: String {
        guard let caption, !caption.isEmpty else { return model.title }
        return "\(caption) › \(model.title)"
    }

    private var caption: String? { model.caption }

    @ViewBuilder
    private var statusLine: some View {
        switch model.status {
        case .editing:
            EmptyView()
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Sending…").foregroundStyle(theme.subtext)
            }
            .font(.system(size: 12))
        case .done(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
                .lineLimit(2)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .lineLimit(3)
        }
    }
}
