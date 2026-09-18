import AppKit
import SwiftUI

extension Color {
    /// "#RRGGBB" (sRGB); nil for anything else.
    init?(hex: String?) {
        guard var s = hex, s.hasPrefix("#") else { return nil }
        s.removeFirst()
        guard s.count == 6, s.allSatisfy(\.isASCII), s.allSatisfy(\.isHexDigit), let v = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255, opacity: 1)
    }
}

/// Brand colors for the popup, resolved for the current color scheme.
struct PopupPalette {
    let cardFill, cardBorder, primary, secondary, blue, chipBackground, chipText: Color
    let pillBackground, pillText, progressTrack, joinText, surface: Color

    init(_ scheme: ColorScheme) {
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
        if scheme == .dark {
            cardFill = Color(hex: "#1A2545")!
            cardBorder = Color(hex: "#2F3F6B")!
            primary = rgb(0.94, 0.96, 1.0)
            secondary = rgb(0.65, 0.71, 0.83)
            blue = rgb(0.30, 0.58, 1.0)
            chipBackground = rgb(0.29, 0.20, 0.06)
            chipText = rgb(1.0, 0.82, 0.54)
            pillBackground = rgb(0.12, 0.21, 0.40)
            pillText = rgb(0.75, 0.85, 1.0)
            progressTrack = Color(hex: "#2A3658")!
            joinText = rgb(0.04, 0.07, 0.15)
            surface = rgb(0.07, 0.10, 0.19)
        } else {
            cardFill = Color(hex: "#FFFFFF")!
            cardBorder = Color(hex: "#E7DCCB")!
            primary = rgb(0.11, 0.16, 0.33)
            secondary = rgb(0.36, 0.42, 0.55)
            blue = rgb(0.18, 0.48, 0.96)
            chipBackground = rgb(1.0, 0.906, 0.76)
            chipText = rgb(0.54, 0.29, 0.0)
            pillBackground = rgb(0.87, 0.92, 1.0)
            pillText = rgb(0.10, 0.34, 0.72)
            progressTrack = Color(hex: "#E7DCCB")!
            joinText = .white
            surface = rgb(1.0, 0.973, 0.94)
        }
    }
}
