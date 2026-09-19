import SwiftUI

/// Small "Beta" capsule shown next to experimental settings.
struct BetaBadge: View {
    var body: some View {
        Text("Beta")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .accessibilityLabel("Beta feature")
    }
}
