import SwiftUI
import AppKit

/// DisplayPlus design tokens — the single source of truth for spacing, sizing,
/// color, and typography across the menu UI. No view should hardcode these values.
///
enum Theme {
    // MARK: Spacing scale (pt)
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8

    // MARK: Row metrics
    static let rowVPadding: CGFloat = 3
    static let rowHPadding: CGFloat = 12
    static let iconSize: CGFloat = 16
    static let iconCorner: CGFloat = 4
    static let iconGlyph: CGFloat = 10       // SF Symbol point size inside the chip

    // MARK: Popover frame
    static let popoverWidth: CGFloat = 340
    static let popoverMinHeight: CGFloat = 360
    static let popoverHeightMargin: CGFloat = 24 // headroom below the menu bar / above the Dock

    // MARK: Colors
    /// The single brand accent — replaces the old system blue everywhere: icon chips, the "Main"
    /// badge, active/link affordances, and (via `.tint`) native toggles/sliders.
    static let accent = Color(red: 0x6A/255.0, green: 0x5A/255.0, blue: 0xE0/255.0) // ~#6A5AE0 mid-violet
    static let secondaryText: Color = .secondary
    static let hoverOpacity: Double = 0.06
    static let dividerOpacity: Double = 0.3

    // MARK: Card grouping
    static let cardCornerRadius: CGFloat = 10
    static let cardInset: CGFloat = 8            // horizontal margin so cards float off the popover edge
    static let cardSpacing: CGFloat = 8          // vertical gap between cards
    static let cardContentVPadding: CGFloat = 4  // padding inside a card, above/below its rows
    static let cardFill = Color.primary.opacity(0.04) // subtle fill over the system material
    static let sectionHeaderTopPadding: CGFloat = 6

    /// Standard row hover background.
    static func hover(_ isHovered: Bool) -> Color {
        Color.primary.opacity(isHovered ? hoverOpacity : 0)
    }

    /// Adaptive popover max height derived from the active screen's visible frame.
    /// Evaluated when the view body is built; OS may still clamp near screen edges.
    static var popoverMaxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - popoverHeightMargin
    }
}
