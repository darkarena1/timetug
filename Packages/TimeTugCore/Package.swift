// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TimeTugCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TimeTugCore", targets: ["TimeTugCore"])],
    dependencies: [.package(path: "../CalendarConnectors")],
    targets: [
        .target(name: "TimeTugCore", dependencies: [.product(name: "CalendarCore", package: "CalendarConnectors")]),
        .testTarget(name: "TimeTugCoreTests", dependencies: [
            "TimeTugCore", .product(name: "CalendarCore", package: "CalendarConnectors"),
        ]),
    ]
)
