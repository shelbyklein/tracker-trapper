// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrackerTrapper",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TrackerTrapperCore", targets: ["TrackerTrapperCore"]),
        .executable(name: "tracker-trapper", targets: ["TrackerTrapperCLI"]),
        .executable(name: "TrackerTrapperMenuBar", targets: ["TrackerTrapperMenuBar"])
    ],
    targets: [
        .target(name: "TrackerTrapperCore"),
        .executableTarget(name: "TrackerTrapperCLI", dependencies: ["TrackerTrapperCore"]),
        .executableTarget(name: "TrackerTrapperMenuBar", dependencies: ["TrackerTrapperCore"]),
        .testTarget(name: "TrackerTrapperCoreTests", dependencies: ["TrackerTrapperCore"])
    ]
)
