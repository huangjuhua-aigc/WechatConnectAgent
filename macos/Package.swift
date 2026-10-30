// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChatInbox",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ChatInbox", targets: ["ChatInboxApp"]),
        .executable(name: "ChatInboxShare", targets: ["ChatInboxShare"])
    ],
    targets: [
        .target(name: "ChatInboxCore", swiftSettings: [.unsafeFlags(["-application-extension"])]),
        .executableTarget(name: "ChatInboxApp", dependencies: ["ChatInboxCore"]),
        .executableTarget(name: "ChatInboxShare", dependencies: ["ChatInboxCore"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"])]),
        .testTarget(name: "ChatInboxCoreTests", dependencies: ["ChatInboxCore"])
    ],
    swiftLanguageVersions: [.v5]
)
