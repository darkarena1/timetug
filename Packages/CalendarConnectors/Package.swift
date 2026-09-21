// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarConnectors",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CalendarCore", targets: ["CalendarCore"]),
        .library(name: "CalendarOAuth", targets: ["CalendarOAuth"]),
        .library(name: "GoogleCalendar", targets: ["GoogleCalendar"]),
        .library(name: "CalendarTestSupport", targets: ["CalendarTestSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "5.0.0"),
    ],
    targets: [
        .target(name: "CalendarCore"),
        .target(name: "CalendarOAuth", dependencies: ["CalendarCore", .product(name: "Crypto", package: "swift-crypto")]),
        .target(name: "GoogleCalendar", dependencies: ["CalendarCore", "CalendarOAuth"]),
        .target(name: "CalendarTestSupport", dependencies: ["CalendarCore"]),
        .testTarget(name: "CalendarCoreTests", dependencies: ["CalendarCore", "CalendarTestSupport"]),
        .testTarget(name: "CalendarOAuthTests", dependencies: ["CalendarOAuth", "CalendarCore", "CalendarTestSupport"]),
        .testTarget(name: "GoogleCalendarTests", dependencies: ["GoogleCalendar", "CalendarOAuth", "CalendarCore", "CalendarTestSupport"]),
    ]
)
