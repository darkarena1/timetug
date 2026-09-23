import SwiftUI

/// System Settings-style icon: a white glyph on a colored rounded square.
struct SettingsRowIcon: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.545, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}

/// A sidebar pane's icon, drawn with `SettingsRowIcon`.
struct PaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        SettingsRowIcon(systemImage: pane.systemImage, color: pane.iconColor)
    }
}
