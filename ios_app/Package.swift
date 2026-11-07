// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenScaleCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "OpenScaleCore", targets: ["OpenScaleCore"])],
    targets: [
        .target(name: "OpenScaleCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "OpenScaleCoreTests", dependencies: ["OpenScaleCore"]),
    ]
)
