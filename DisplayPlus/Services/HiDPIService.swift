import Foundation
import CoreGraphics

/// Manages HiDPI ("Retina") scaling for external displays by activating the scaled HiDPI modes that
/// macOS generates but hides from the public `CGDisplayCopyAllDisplayModes` API.
///
/// This is the same mechanism BetterDisplay uses — no virtual display, no mirroring, no
/// `/Library/Displays` plist override, no administrator rights. The heavy lifting (enumerating and
/// activating the private modes) lives in `CGSDisplayService`; this service adds policy
/// (which mode to pick), persistence, and re-application after sleep/wake and reconnect.
///
/// Preference is keyed by `DisplayInfo.displayUUID` (stable across hot-plug / display-ID churn).
@MainActor
final class HiDPIService: @unchecked Sendable {
    static let shared = HiDPIService()
    private init() {}

    private var refreshTask: Task<Void, Never>?

    /// A selectable HiDPI scaling level for the UI — a "looks like" logical resolution rendered at
    /// Retina density. Value type so the view layer never touches `CGSDisplayService` directly.
    struct ScaleOption: Identifiable, Equatable {
        let modeNumber: Int32
        let width: Int       // logical ("looks like") width in points
        let height: Int      // logical ("looks like") height in points
        let refresh: Int     // Hz
        var id: Int32 { modeNumber }
        var label: String { "\(width) × \(height)" }
    }

    /// `fd.`-prefixed UserDefaults key: per-display HiDPI on/off preference, keyed by display UUID.
    private static let enabledKeyPrefix = "fd.hidpi.enabled."
    private func enabledKey(_ uuid: String) -> String { Self.enabledKeyPrefix + uuid }

    /// `fd.`-prefixed key: the chosen HiDPI "looks like" resolution ("WxH"), so the exact scale the
    /// user picked is restored on wake/reconnect — not just "some HiDPI mode".
    private static let scaleKeyPrefix = "fd.hidpi.scale."
    private func scaleKey(_ uuid: String) -> String { Self.scaleKeyPrefix + uuid }

    // MARK: - Preference (persisted)

    /// Whether the user has an explicit HiDPI preference stored for this display.
    func hasPreference(uuid: String) -> Bool {
        UserDefaults.standard.object(forKey: enabledKey(uuid)) != nil
    }

    /// The persisted HiDPI preference (false if none stored).
    func isHiDPIPreferred(uuid: String) -> Bool {
        UserDefaults.standard.bool(forKey: enabledKey(uuid))
    }

    private func setPreferred(_ on: Bool, uuid: String) {
        UserDefaults.standard.set(on, forKey: enabledKey(uuid))
    }

    /// The persisted "looks like" scale the user last chose for this display, if any.
    func preferredScale(uuid: String) -> (width: Int, height: Int)? {
        guard let s = UserDefaults.standard.string(forKey: scaleKey(uuid)) else { return nil }
        let parts = s.split(separator: "x")
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else { return nil }
        return (w, h)
    }

    private func setScale(width: Int, height: Int, uuid: String) {
        UserDefaults.standard.set("\(width)x\(height)", forKey: scaleKey(uuid))
    }

    private func clearScale(uuid: String) {
        UserDefaults.standard.removeObject(forKey: scaleKey(uuid))
    }

    /// Forget the HiDPI preference without touching the active mode. Used when a preset selects a
    /// plain (non-HiDPI) resolution so wake/reconnect reapply won't fight it back into HiDPI.
    func clearPreference(uuid: String) {
        setPreferred(false, uuid: uuid)
        clearScale(uuid: uuid)
    }

    // MARK: - Live state

    /// True when the display's **current active** mode is a HiDPI (Retina) mode.
    func isHiDPIActive(for displayID: CGDirectDisplayID) -> Bool {
        guard let cur = CGSDisplayService.currentModeNumber(for: displayID) else { return false }
        return CGSDisplayService.modes(for: displayID).first { $0.number == cur }?.isHiDPI ?? false
    }

    /// The "looks like" logical resolution of the current mode, but only when it is a HiDPI mode.
    /// Returns nil when the display is at a plain 1× mode — used by the UI to mark the active scale.
    func currentScale(for displayID: CGDirectDisplayID) -> (width: Int, height: Int)? {
        guard let cur = CGSDisplayService.currentModeNumber(for: displayID),
              let m = CGSDisplayService.modes(for: displayID).first(where: { $0.number == cur }),
              m.isHiDPI else { return nil }
        return (m.width, m.height)
    }

    /// The selectable HiDPI scaling levels for this display, largest logical area first.
    /// Each is a "looks like" resolution rendered at Retina density — exactly what BetterDisplay lists.
    func scaleOptions(for displayID: CGDirectDisplayID) -> [ScaleOption] {
        candidateHiDPIModes(for: displayID).map {
            ScaleOption(modeNumber: $0.number, width: $0.width, height: $0.height, refresh: $0.refresh)
        }
    }

    /// Every hidden HiDPI mode as a value-typed option — **one per refresh-rate variant**, not deduped.
    /// Used by the unified Display Mode list so each Retina resolution can offer a refresh-rate picker.
    /// Filtered to desktop-usable sizes (>= 1280×720) to match the public mode list.
    func hiDPIModeOptions(for displayID: CGDirectDisplayID) -> [ScaleOption] {
        CGSDisplayService.modes(for: displayID)
            .filter { $0.isHiDPI && !$0.isStretched && $0.width >= 1280 && $0.height >= 720 }
            .map { ScaleOption(modeNumber: $0.number, width: $0.width, height: $0.height, refresh: $0.refresh) }
    }

    // MARK: - Mode selection

    /// Usable HiDPI desktop modes (Retina, not stretched, sane logical size), one per logical
    /// resolution (highest refresh kept), sorted by logical area descending.
    func candidateHiDPIModes(for displayID: CGDirectDisplayID) -> [CGSDisplayService.Mode] {
        let raw = CGSDisplayService.modes(for: displayID)
            .filter { $0.isHiDPI && !$0.isStretched && $0.width >= 1024 && $0.height >= 720 }
        var best: [String: CGSDisplayService.Mode] = [:]
        for m in raw {
            let key = "\(m.width)x\(m.height)"
            if let existing = best[key], existing.refresh >= m.refresh { continue }
            best[key] = m
        }
        return best.values.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
    }

    /// The HiDPI mode for a specific "looks like" logical size, at the refresh rate closest to the
    /// current one (highest refresh breaks ties). Returns nil if no such Retina mode exists.
    private func hiDPIMode(for displayID: CGDirectDisplayID,
                           logicalWidth: Int, logicalHeight: Int) -> CGSDisplayService.Mode? {
        let currentRefresh = currentRefresh(for: displayID)
        let matches = CGSDisplayService.modes(for: displayID)
            .filter { $0.isHiDPI && !$0.isStretched && $0.width == logicalWidth && $0.height == logicalHeight }
        // Prefer the refresh rate matching the current mode; otherwise the highest available.
        return matches.min { lhs, rhs in
            let dl = abs(lhs.refresh - currentRefresh)
            let dr = abs(rhs.refresh - currentRefresh)
            if dl != dr { return dl < dr }
            return lhs.refresh > rhs.refresh
        }
    }

    /// The "looks like native" HiDPI mode (logical size == native pixels) — full desktop space
    /// rendered crisply at 2×. This is the default "enable" when the user has no saved scale.
    private func nativeHiDPIMode(for displayID: CGDirectDisplayID,
                                 nativeWidth: Int, nativeHeight: Int) -> CGSDisplayService.Mode? {
        hiDPIMode(for: displayID, logicalWidth: nativeWidth, logicalHeight: nativeHeight)
    }

    /// The "looks like native" 1× mode (used to turn HiDPI off), refresh closest to current.
    private func native1xMode(for displayID: CGDirectDisplayID,
                              nativeWidth: Int, nativeHeight: Int) -> CGSDisplayService.Mode? {
        let currentRefresh = currentRefresh(for: displayID)
        let matches = CGSDisplayService.modes(for: displayID)
            .filter { !$0.isHiDPI && $0.width == nativeWidth && $0.height == nativeHeight }
        guard !matches.isEmpty else { return nil }
        return matches.min { abs($0.refresh - currentRefresh) < abs($1.refresh - currentRefresh) }
    }

    private func currentRefresh(for displayID: CGDirectDisplayID) -> Int {
        guard let cur = CGSDisplayService.currentModeNumber(for: displayID) else { return 60 }
        return CGSDisplayService.modes(for: displayID).first { $0.number == cur }?.refresh ?? 60
    }

    // MARK: - Enable / disable

    /// Activates HiDPI and remembers the preference. Restores the user's saved "looks like" scale if
    /// one exists, otherwise picks "looks like native", otherwise the largest available HiDPI mode.
    /// Returns nil on success, or a human-readable error string on failure.
    @discardableResult
    func enableHiDPI(for displayID: CGDirectDisplayID, uuid: String,
                     nativeWidth: Int, nativeHeight: Int) async -> String? {
        guard CGSDisplayService.isAvailable else { return "HiDPI is not supported on this system" }
        let saved = preferredScale(uuid: uuid)
            .flatMap { hiDPIMode(for: displayID, logicalWidth: $0.width, logicalHeight: $0.height) }
        let target = saved
            ?? nativeHiDPIMode(for: displayID, nativeWidth: nativeWidth, nativeHeight: nativeHeight)
            ?? candidateHiDPIModes(for: displayID).first
        guard let target else { return "No HiDPI mode is available for this display" }

        // Runs on the main actor — the CGS config transaction needs the main runloop (see CGSDisplayService).
        guard CGSDisplayService.setMode(target.number, for: displayID) else {
            return "Failed to activate HiDPI mode"
        }
        setPreferred(true, uuid: uuid)
        setScale(width: target.width, height: target.height, uuid: uuid)
        return nil
    }

    /// Activates a specific HiDPI "looks like" scale (from `scaleOptions`) and remembers it.
    /// Returns nil on success, or a human-readable error string on failure.
    @discardableResult
    func applyScale(width: Int, height: Int,
                    for displayID: CGDirectDisplayID, uuid: String) async -> String? {
        guard CGSDisplayService.isAvailable else { return "HiDPI is not supported on this system" }
        guard let target = hiDPIMode(for: displayID, logicalWidth: width, logicalHeight: height) else {
            return "That HiDPI scale is not available for this display"
        }
        guard CGSDisplayService.setMode(target.number, for: displayID) else {
            return "Failed to activate HiDPI mode"
        }
        setPreferred(true, uuid: uuid)
        setScale(width: target.width, height: target.height, uuid: uuid)
        return nil
    }

    /// Activates a **specific** CGS mode by its number (the exact resolution *and* refresh the user
    /// picked from the unified Display Mode list). Updates the HiDPI preference: a HiDPI mode is
    /// remembered (so wake/reconnect restore it); a non-HiDPI mode clears it. Returns nil on success.
    @discardableResult
    func applyMode(number: Int32, width: Int, height: Int, isHiDPI: Bool,
                   for displayID: CGDirectDisplayID, uuid: String) async -> String? {
        guard CGSDisplayService.isAvailable else { return "HiDPI is not supported on this system" }
        guard CGSDisplayService.setMode(number, for: displayID) else {
            return "Failed to activate this display mode"
        }
        if isHiDPI {
            setPreferred(true, uuid: uuid)
            setScale(width: width, height: height, uuid: uuid)
        } else {
            setPreferred(false, uuid: uuid)
            clearScale(uuid: uuid)
        }
        return nil
    }

    /// Reverts to the native 1× mode and clears the HiDPI preference (and saved scale).
    /// Returns nil on success, or a human-readable error string on failure.
    @discardableResult
    func disableHiDPI(for displayID: CGDirectDisplayID, uuid: String,
                      nativeWidth: Int, nativeHeight: Int) async -> String? {
        setPreferred(false, uuid: uuid)
        clearScale(uuid: uuid)
        guard let target = native1xMode(for: displayID, nativeWidth: nativeWidth, nativeHeight: nativeHeight) else {
            return "No native (1×) mode is available for this display"
        }
        guard CGSDisplayService.setMode(target.number, for: displayID) else {
            return "Failed to revert to native mode"
        }
        return nil
    }

    // MARK: - Reapply (wake / reconnect)

    /// Re-activates the preferred HiDPI mode if the user enabled it but the display reverted
    /// (macOS resets to a 1× mode on reconnect / wake). No-op if HiDPI isn't preferred or is already active.
    func reapplyIfNeeded(for displayID: CGDirectDisplayID, uuid: String,
                         nativeWidth: Int, nativeHeight: Int) {
        guard isHiDPIPreferred(uuid: uuid), !isHiDPIActive(for: displayID) else { return }
        Task { await self.enableHiDPI(for: displayID, uuid: uuid,
                                      nativeWidth: nativeWidth, nativeHeight: nativeHeight) }
    }

    // MARK: - Mode list refresh

    /// Refreshes `availableModes` / `currentDisplayMode` on the given DisplayInfo after a mode change.
    func refreshModes(for display: DisplayInfo) {
        refreshTask?.cancel()
        let physicalID = display.displayID
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            async let modes = Task.detached(priority: .userInitiated) {
                DisplayMode.availableModes(for: physicalID)
            }.value
            async let current = Task.detached(priority: .userInitiated) {
                DisplayMode.currentMode(for: physicalID)
            }.value
            display.availableModes = await modes
            display.currentDisplayMode = await current
        }
    }
}
