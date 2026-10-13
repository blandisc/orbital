// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OrbitalCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "OrbitalCore", targets: ["OrbitalCore"]),
        .library(name: "OrbitalModels", targets: ["OrbitalModels"]),
    ],
    targets: [
        .target(name: "OrbitalCore"),
        .target(name: "OrbitalModels", dependencies: ["OrbitalCore"]),
        .testTarget(name: "OrbitalCoreTests", dependencies: ["OrbitalCore"]),
        .testTarget(name: "OrbitalModelsTests", dependencies: ["OrbitalModels", "OrbitalCore"]),
    ]
)
