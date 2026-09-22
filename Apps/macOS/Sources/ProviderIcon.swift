import SwiftUI

/// The small mark shown beside an internet account. Drawn here (no bundled brand artwork); unknown providers get a person icon.
struct ProviderIcon: View {
    enum Style: Equatable {
        case google, generic

        static func forKind(_ kindID: String) -> Style {
            kindID == "google" ? .google : .generic
        }
    }

    let kindID: String
    var size: CGFloat = 26

    /// "google" gives "Google"; kinds without a special name are just capitalised.
    static func displayName(forKindID kindID: String) -> String {
        kindID.prefix(1).uppercased() + kindID.dropFirst()
    }

    var body: some View {
        Group {
            switch Style.forKind(kindID) {
            case .google: GoogleMark().padding(size * 0.2)
            case .generic:
                Image(systemName: "person.crop.circle")
                    .resizable().scaledToFit().foregroundStyle(.secondary).padding(size * 0.1)
            }
        }
        .frame(width: size, height: size)
        .background(Style.forKind(kindID) == .google ? AnyShapeStyle(.white) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: size * 0.22))
        .accessibilityHidden(true)
    }
}

/// A four-colour "G": arcs of a ring plus the crossbar. Angles are fractions of a turn from 3 o'clock, clockwise.
private struct GoogleMark: View {
    private static let red = Color(red: 0.92, green: 0.26, blue: 0.21)
    private static let blue = Color(red: 0.26, green: 0.52, blue: 0.96)
    private static let green = Color(red: 0.20, green: 0.66, blue: 0.33)
    private static let yellow = Color(red: 0.98, green: 0.74, blue: 0.02)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let line = side * 0.24
            ZStack {
                arc(0.0, 0.13, Self.blue, line, side)
                arc(0.13, 0.36, Self.green, line, side)
                arc(0.36, 0.56, Self.yellow, line, side)
                arc(0.56, 0.875, Self.red, line, side)
                Rectangle().fill(Self.blue)
                    .frame(width: side * 0.46, height: line)
                    .position(x: side * 0.73, y: side / 2)
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func arc(_ from: Double, _ to: Double, _ color: Color, _ line: CGFloat, _ side: CGFloat) -> some View {
        Circle().trim(from: from, to: to)
            .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .butt))
            .padding(line / 2)
    }
}
