# ADR 0001: Swift and Native Stack

**Status:** Accepted

## Context

TimeTug is a macOS menu bar application that needs to integrate tightly with the system, access calendar data, and manage full-screen overlays on multiple displays. The implementation requires both a shared cross-platform core and native platform frontends.

## Decision

Use Swift as the primary language with SwiftUI and AppKit for the macOS frontend, organized as Swift Package Manager modules. `Packages/TimeTugCore` is pure Swift with no platform dependencies; `Packages/EventKitSource` wraps Apple Calendar via EventKit; `Apps/macOS` is the native entry point.

Rejected alternatives:
- **Rust core + native shell:** Would require language interoperability, limiting Swift's ecosystem on Windows/Linux and complicating maintenance. Swift SPM modules scale better for a team favoring macOS-first development.
- **Tauri/Electron:** These introduce an embedded web runtime, increasing memory overhead and system tray complexity on macOS. Native AppKit integration for overlay windows and accessibility labels is cleaner without a web bridge.

## Consequences

**Advantages:**
- Direct AppKit integration for system-level features (menu bar, window levels, display tracking).
- SwiftUI and Swift Concurrency simplify async event handling and state management.
- Single language across Core and frontend reduces cognitive load.

**Trade-off:** Swift maturity on Windows and Linux lags macOS. Mitigation: `CalendarSource` protocol enables a future Rust port of Core (sources return only Swift models) if Windows support becomes critical. The protocol defines the API boundary, not the implementation language.

The bet: a pure-Swift iOS frontend or Windows .NET frontend can import and re-implement `CalendarSource` independently, while Core stays Swift-native on macOS.
