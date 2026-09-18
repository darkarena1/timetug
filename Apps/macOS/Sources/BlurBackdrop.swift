import AppKit
import SwiftUI

/// A live blur of whatever is behind the window. The hosting window must be non-opaque with a clear background.
struct BlurBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Shared backdrop of every takeover window: blur plus a brand-navy tint, or solid navy under Reduce Transparency.
struct TakeoverBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if !reduceTransparency { BlurBackdrop() }
            TakeoverColors.navy.opacity(reduceTransparency ? 0.97 : 0.62)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Brand colors used on the takeover screen.
enum TakeoverColors {
    static let navy = Color(red: 0.05, green: 0.08, blue: 0.16)
    static let calm = Color(red: 0.85, green: 0.91, blue: 1.0)
    static let orange = Color(red: 1.0, green: 0.69, blue: 0.23)
    static let redOrange = Color(red: 1.0, green: 0.42, blue: 0.29)
    static let muted = Color(red: 0.65, green: 0.71, blue: 0.83)
    static let hint = Color(red: 0.5, green: 0.56, blue: 0.68)
    static let blue = Color(red: 0.30, green: 0.58, blue: 1.0)
    static let onBlue = Color(red: 0.04, green: 0.07, blue: 0.15)

    static func headline(_ tone: TakeoverText.Tone) -> Color {
        switch tone {
        case .calm: return calm
        case .urgent: return orange
        case .late: return redOrange
        }
    }
}
