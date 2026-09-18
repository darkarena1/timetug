// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TimeTugCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TimeTugCore", targets: ["TimeTugCore"])],
    targets: [
        .target(name: "TimeTugCore"),
        .testTarget(name: "TimeTugCoreTests", dependencies: ["TimeTugCore"]),
    ]
)
