// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EventKitSource",
    platforms: [.macOS(.v14)],
    products: [.library(name: "EventKitSource", targets: ["EventKitSource"])],
    dependencies: [.package(path: "../CalendarConnectors")],
    targets: [
        .target(
            name: "EventKitSource",
            dependencies: [.product(name: "CalendarCore", package: "CalendarConnectors")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "EventKitSourceTests",
            dependencies: [
                "EventKitSource",
                .product(name: "CalendarCore", package: "CalendarConnectors"),
                .product(name: "CalendarTestSupport", package: "CalendarConnectors"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
