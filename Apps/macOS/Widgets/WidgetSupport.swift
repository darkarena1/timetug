import SwiftUI

extension Color {
    /// Accepts the "#RRGGBB" form Core normalizes to; falls back to the accent colour.
    init(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else {
            self = .accentColor
            return
        }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

struct OpenAppPlaceholder: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.clock").font(.title2)
            Text("Open TimeTug to load your meetings")
                .font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }
}
