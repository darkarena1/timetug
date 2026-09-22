import SwiftUI

/// System Settings-style icon: a white glyph on a colored rounded square.
struct SettingsRowIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color, in: RoundedRectangle(cornerRadius: 5.5, style: .continuous))
    }
}

/// A sidebar pane's icon, drawn with `SettingsRowIcon`.
struct PaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        SettingsRowIcon(systemImage: pane.systemImage, color: pane.iconColor)
    }
}
