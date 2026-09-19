// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleIntelligenceInference",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AppleIntelligenceInference", targets: ["AppleIntelligenceInference"])],
    dependencies: [.package(path: "../TimeTugCore")],
    targets: [
        .target(
            name: "AppleIntelligenceInference",
            dependencies: [.product(name: "TimeTugCore", package: "TimeTugCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AppleIntelligenceInferenceTests",
            dependencies: ["AppleIntelligenceInference", .product(name: "TimeTugCore", package: "TimeTugCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
