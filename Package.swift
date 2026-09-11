// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SnapPile",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SnapPile", targets: ["SnapPile"]),
        .library(name: "SnapPileCore", targets: ["SnapPileCore"]),
    ],
    targets: [
        .target(name: "SnapPileCore"),
        .executableTarget(
            name: "SnapPile", dependencies: ["SnapPileCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "SnapPileCoreTests", dependencies: ["SnapPileCore"]),
        .testTarget(name: "SnapPileAppTests", dependencies: ["SnapPile", "SnapPileCore"]),
    ]
)
