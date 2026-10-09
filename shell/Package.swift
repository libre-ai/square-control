// swift-tools-version: 6.0
import PackageDescription

// Zero third-party Swift package (NFR-S8). The Rust core arrives as a local xcframework
// built by scripts/build-core.sh; it is never committed.
let package = Package(
    name: "SquareControl",
    platforms: [.macOS("26.0")],
    targets: [
        .binaryTarget(name: "SCCoreFFI", path: "../xcframework/SCCoreFFI.xcframework"),
        .target(
            name: "SCCore",
            dependencies: ["SCCoreFFI"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .target(
            name: "SquareControlKit",
            dependencies: ["SCCore"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])],
            linkerSettings: [.linkedFramework("ApplicationServices"), .linkedFramework("Carbon")]
        ),
        .executableTarget(
            name: "SquareControl",
            dependencies: ["SquareControlKit"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])],
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        // P3 probe, never shipped in the app bundle.
        .executableTarget(
            name: "sc-axmech",
            dependencies: ["SquareControlKit", "SCCore"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "SquareControlKitTests",
            dependencies: ["SquareControlKit", "SCCore"]
        ),
    ]
)
