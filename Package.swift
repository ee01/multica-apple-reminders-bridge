// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MulticaAppleRemindersBridge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BridgeCore", targets: ["BridgeCore"]),
        .executable(name: "MulticaRemindersBridge", targets: ["MulticaRemindersBridge"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: "sqlite3",
            providers: [
                .brew(["sqlite3"]),
                .apt(["libsqlite3-dev"])
            ]
        ),
        .target(
            name: "BridgeCore",
            dependencies: ["CSQLite"],
            path: "Sources/BridgeCore"
        ),
        .executableTarget(
            name: "MulticaRemindersBridge",
            dependencies: ["BridgeCore"],
            path: "Sources/MulticaRemindersBridge"
        ),
        .testTarget(
            name: "BridgeCoreTests",
            dependencies: ["BridgeCore"],
            path: "Tests/BridgeCoreTests"
        )
    ]
)
