import SwiftUI

/// A higher-contrast checkbox: secondary-colored outline when off, accent fill with a checkmark when on.
struct ContrastCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack {
                if configuration.isOn {
                    RoundedRectangle(cornerRadius: 4).fill(Color.accentColor)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    RoundedRectangle(cornerRadius: 4).stroke(Color.secondary, lineWidth: 1.5)
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
