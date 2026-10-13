// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OrbitalCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "OrbitalCore", targets: ["OrbitalCore"])],
    targets: [
        .target(name: "OrbitalCore"),
        .testTarget(name: "OrbitalCoreTests", dependencies: ["OrbitalCore"]),
    ]
)
