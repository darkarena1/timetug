import SwiftUI

/// System Settings-style pane icon: a white glyph on a colored rounded square.
struct PaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        Image(systemName: pane.systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(pane.iconColor, in: RoundedRectangle(cornerRadius: 5.5, style: .continuous))
    }
}
