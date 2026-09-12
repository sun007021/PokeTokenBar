// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PokeTokenBarExtended",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MobiusCore",
            path: "Sources/MobiusCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PokeTokenBarExtended",
            dependencies: ["MobiusCore"],
            path: "Sources/PokeTokenBarExtended",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "PokeTokenBarExtendedTests",
            dependencies: ["PokeTokenBarExtended"],
            path: "Tests/PokeTokenBarExtendedTests",
            resources: [
                .copy("Fixtures/CodexFork"),
                .copy("Fixtures/CodexSubagent"),
            ]
        ),
        .testTarget(
            name: "MobiusCoreTests",
            dependencies: ["MobiusCore"],
            path: "Tests/MobiusCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
