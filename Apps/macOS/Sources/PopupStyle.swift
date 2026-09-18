import CoreGraphics

/// Tunables for the menu bar popup.
enum PopupStyle {
    /// false: the popover keeps its native translucent material and only the cards are solid.
    /// true: the popup content also paints a solid brand surface (cream in light, deep navy in dark).
    static let usesSolidBackground = false

    static let width: CGFloat = 360
    /// Tallest the whole popup gets; past this the day list scrolls and the header stays put.
    static let maxHeight: CGFloat = 520
}
