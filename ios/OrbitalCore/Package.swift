// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OrbitalCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "OrbitalCore", targets: ["OrbitalCore"]),
        .library(name: "OrbitalModels", targets: ["OrbitalModels"]),
        .library(name: "OrbitalAddons", targets: ["OrbitalAddons"]),
    ],
    targets: [
        // Tus complementos y tu servicio de descarga (Real-Debrid), sin saber de Stremio ni de Trakt: solo Foundation.
        .target(name: "OrbitalAddons"),
        .target(name: "OrbitalCore", dependencies: ["OrbitalAddons"]),
        .target(name: "OrbitalModels", dependencies: ["OrbitalCore", "OrbitalAddons"]),
        .testTarget(name: "OrbitalCoreTests", dependencies: ["OrbitalCore", "OrbitalAddons"]),
        .testTarget(name: "OrbitalModelsTests", dependencies: ["OrbitalModels", "OrbitalCore", "OrbitalAddons"]),
        .testTarget(name: "OrbitalAddonsTests", dependencies: ["OrbitalAddons"]),
    ]
)
