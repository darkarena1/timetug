// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarBridge",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CalendarBridge", targets: ["CalendarBridge"])],
    dependencies: [.package(path: "../TimeTugCore"), .package(path: "../CalendarConnectors")],
    targets: [
        .target(name: "CalendarBridge", dependencies: [
            .product(name: "TimeTugCore", package: "TimeTugCore"),
            .product(name: "CalendarCore", package: "CalendarConnectors"),
        ]),
        .testTarget(name: "CalendarBridgeTests", dependencies: [
            "CalendarBridge",
            .product(name: "TimeTugCore", package: "TimeTugCore"),
            .product(name: "CalendarCore", package: "CalendarConnectors"),
        ]),
    ]
)
