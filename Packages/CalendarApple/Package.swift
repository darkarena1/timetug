// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarApple",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CalendarApple", targets: ["CalendarApple"])],
    dependencies: [.package(path: "../CalendarConnectors")],
    targets: [
        .target(name: "CalendarApple", dependencies: [.product(name: "CalendarCore", package: "CalendarConnectors"),
                               .product(name: "CalendarOAuth", package: "CalendarConnectors")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CalendarAppleTests", dependencies: ["CalendarApple", .product(name: "CalendarCore", package: "CalendarConnectors"),
                                   .product(name: "CalendarOAuth", package: "CalendarConnectors")],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
