// swift-tools-version:6.0
import Foundation
import PackageDescription

// With only the Command Line Tools installed (no Xcode), swift-testing lives here and isn't on the
// default search path. Point the test target at it when present.
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let activeDeveloperDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link")) ?? ""
let needsCLTTesting = activeDeveloperDir.hasPrefix("/Library/Developer/CommandLineTools")
    && FileManager.default.fileExists(atPath: cltFrameworks + "/Testing.framework")
let testSwiftSettings: [SwiftSetting] = needsCLTTesting ? [.unsafeFlags(["-F", cltFrameworks])] : []
let testLinkerSettings: [LinkerSetting] = needsCLTTesting
    ? [.unsafeFlags(["-F", cltFrameworks, "-Xlinker", "-rpath", "-Xlinker", cltFrameworks])] : []

let package = Package(
    name: "TheOneRing",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: config model, wheel geometry, key-combo parsing. No AppKit, fully unit-tested.
        .target(name: "RingCore"),
        // The menu-bar app: hotkey, overlay panel, SwiftUI wheel, settings window, action runner.
        .executableTarget(
            name: "TheOneRing",
            dependencies: ["RingCore"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(
            name: "RingCoreTests",
            dependencies: ["RingCore"],
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        ),
    ],
    swiftLanguageModes: [.v5]
)
