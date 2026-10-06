// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClaudeBarCore"),
        .testTarget(name: "ClaudeBarCoreTests", dependencies: ["ClaudeBarCore"]),
    ],
    swiftLanguageModes: [.v5]
)
