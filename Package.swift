// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PokeTokenBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MobiusCore",
            path: "Sources/MobiusCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PokeTokenBar",
            dependencies: ["MobiusCore"],
            path: "Sources/PokeTokenBar",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "PokeTokenBarTests",
            dependencies: ["PokeTokenBar"],
            path: "Tests/PokeTokenBarTests",
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
