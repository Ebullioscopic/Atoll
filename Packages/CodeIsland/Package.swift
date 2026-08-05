// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodeIsland",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodeIslandCore", targets: ["CodeIslandCore"]),
        .library(name: "CodeIslandRuntime", targets: ["CodeIslandRuntime"]),
        .library(name: "CodeIslandUI", targets: ["CodeIslandUI"]),
        .executable(name: "codeisland-bridge", targets: ["codeisland-bridge"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CodeIslandCore",
            path: "Sources/CodeIslandCore",
            exclude: ["Upstream"]
        ),
        .target(
            name: "CodeIslandRuntime",
            dependencies: ["CodeIslandCore"],
            path: "Sources/CodeIslandRuntime",
            exclude: ["Upstream"]
        ),
        .target(
            name: "CodeIslandUI",
            dependencies: ["CodeIslandCore"],
            path: "Sources/CodeIslandUI",
            exclude: ["Upstream"],
            resources: [
                .copy("Resources/Sounds"),
                .copy("Resources/ThirdPartyNotices"),
                .process("Resources/CodeIsland.xcstrings"),
            ]
        ),
        .executableTarget(
            name: "codeisland-bridge",
            dependencies: ["CodeIslandRuntime"],
            path: "Sources/CodeIslandBridge"
        ),
        .testTarget(
            name: "CodeIslandRuntimeTests",
            dependencies: ["CodeIslandCore", "CodeIslandRuntime", "CodeIslandUI"],
            path: "Tests/CodeIslandRuntimeTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
