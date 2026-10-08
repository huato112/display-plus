import Foundation
import CoreGraphics

/// Represents a single display mode (resolution + refresh rate + HiDPI flag).
struct DisplayMode: Identifiable, Equatable {
    /// Unique identifier: IODisplayModeID
    let id: Int32
    /// Logical width in points
    let width: Int
    /// Logical height in points
    let height: Int
    /// Physical pixel width (HiDPI: 2× logical)
    let pixelWidth: Int
    /// Physical pixel height
    let pixelHeight: Int
    /// Refresh rate in Hz (0 means display default, shown as 60)
    let refreshRate: Double
    /// Whether this is a HiDPI (Retina) scaled mode
    let isHiDPI: Bool
    /// Raw IODisplayModeID for CGConfigureDisplayWithDisplayMode (same as id)
    var ioDisplayModeID: Int32 { id }

    // MARK: - Display strings

    var resolutionString: String {
        "\(width)×\(height)"
    }

    // MARK: - Enumeration helpers

    /// Returns all display modes for the given display, sorted by logical width descending.
    static func availableModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        let options: CFDictionary = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let rawModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode],
              !rawModes.isEmpty else {
            return []
        }

        var seen = Set<Int32>()
        return rawModes.compactMap { mode -> DisplayMode? in
            let modeID = mode.ioDisplayModeID
            guard seen.insert(modeID).inserted else { return nil }  // deduplicate
            guard mode.isUsableForDesktopGUI() else { return nil }

            let w = mode.width
            let h = mode.height
            let pw = mode.pixelWidth
            let ph = mode.pixelHeight
            let refresh = mode.refreshRate

            return DisplayMode(
                id: modeID,
                width: w,
                height: h,
                pixelWidth: pw,
                pixelHeight: ph,
                refreshRate: refresh,
                isHiDPI: pw > w
            )
        }
        .sorted { lhs, rhs in
            if lhs.width != rhs.width { return lhs.width > rhs.width }
            if lhs.height != rhs.height { return lhs.height > rhs.height }
            if lhs.refreshRate != rhs.refreshRate { return lhs.refreshRate > rhs.refreshRate }
            if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI }
            return false
        }
    }

    /// Returns the current active display mode.
    static func currentMode(for displayID: CGDirectDisplayID) -> DisplayMode? {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return nil }

        let w = mode.width
        let h = mode.height
        let pw = mode.pixelWidth
        let ph = mode.pixelHeight
        let refresh = mode.refreshRate
        let modeID = mode.ioDisplayModeID

        return DisplayMode(
            id: modeID,
            width: w,
            height: h,
            pixelWidth: pw,
            pixelHeight: ph,
            refreshRate: refresh,
            isHiDPI: pw > w
        )
    }
}
