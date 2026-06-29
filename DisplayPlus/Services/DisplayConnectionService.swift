import Foundation
import CoreGraphics

/// Per-display on/off — disconnect / reconnect a display from the desktop arrangement
/// (the BetterDisplay-style feature). The raw mechanism is `CGSDisplayService.setDisplayEnabled`;
/// this service owns policy: safety guards, persistence, and guarded restore on launch/wake.
///
/// Persistence: `fd.display.disconnected.<hardwareID>` (Bool), keyed by `DisplayInfo.hardwareID`
/// (vendor/model/serial). We deliberately do NOT key on `displayUUID`: `CGDisplayCreateUUIDFromDisplayID`
/// is inconsistent across active/disabled state — it can return a real UUID while a display is active
/// but nil once disabled — so a key written at disconnect time would never match the live value later,
/// leaving stale "ghost" entries. `hardwareID` is captured once at init and never flips.
@MainActor
final class DisplayConnectionService: ObservableObject, @unchecked Sendable {
    static let shared = DisplayConnectionService()
    private init() {}

    private let defaults = UserDefaults.standard
    private func key(_ uuid: String) -> String { "fd.display.disconnected.\(uuid)" }

    /// Whether this macOS build exposes the private enable/disable API. UI hides controls when false.
    var isAvailable: Bool { CGSDisplayService.canToggleDisplayEnabled }

    // MARK: - In-session tracking

    /// Displays disconnected by us this session: live `CGDirectDisplayID` → the display's `hardwareID`.
    /// A CGS-disconnected display drops off `CGGetOnlineDisplayList` entirely, so we remember it here
    /// to keep it listed (and reconnectable) in the UI. The persisted `fd.` keys survive a relaunch;
    /// this map survives a single session.
    private var disconnectedByID: [CGDirectDisplayID: String] = [:]

    /// Whether `displayID` is currently disconnected by us — drives the UI's "keep it listed" logic.
    func isDisconnected(displayID: CGDirectDisplayID) -> Bool { disconnectedByID[displayID] != nil }

    // MARK: - Persistence  (keyed by hardwareID)

    func isMarkedDisconnected(hardwareID: String) -> Bool { defaults.bool(forKey: key(hardwareID)) }

    private func setMarked(_ disconnected: Bool, hardwareID: String) {
        if disconnected {
            defaults.set(true, forKey: key(hardwareID))
        } else {
            defaults.removeObject(forKey: key(hardwareID))
        }
    }

    /// The hardwareIDs of every display currently persisted as disconnected (the
    /// `fd.display.disconnected.*` keys set to true).
    private func persistedDisconnectedIDs() -> [String] {
        let prefix = "fd.display.disconnected."
        return defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) && defaults.bool(forKey: $0) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    /// True when a display is persisted as disconnected but isn't among the currently-listed
    /// displays — it dropped off the OS online list (typically after an app restart or reboot) and
    /// can't be shown or reconnected inline. Drives the "Connect all displays" recovery row.
    func hasUnlistedDisconnects(amongListed displays: [DisplayInfo]) -> Bool {
        guard isAvailable else { return false }
        let listed = Set(displays.map { $0.hardwareID })
        return persistedDisconnectedIDs().contains { !listed.contains($0) }
    }

    // MARK: - Guards

    /// Count of displays currently active (participating in the desktop).
    private func activeDisplayCount() -> Int {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        return Int(count)
    }

    // MARK: - Actions  (return nil on success, else a user-facing error string)

    @discardableResult
    func disconnect(_ display: DisplayInfo) -> String? {
        guard isAvailable else { return "This macOS version doesn't expose the display on/off API" }
        guard activeDisplayCount() > 1 else { return "Can't disconnect the only active display" }
        let hwID = display.hardwareID
        guard CGSDisplayService.setDisplayEnabled(false, for: display.displayID) else {
            return "Failed to disconnect this display"
        }
        setMarked(true, hardwareID: hwID)
        disconnectedByID[display.displayID] = hwID
        return nil
    }

    @discardableResult
    func reconnect(_ display: DisplayInfo) -> String? {
        guard isAvailable else { return "This macOS version doesn't expose the display on/off API" }
        guard CGSDisplayService.setDisplayEnabled(true, for: display.displayID) else {
            return "Failed to reconnect this display"
        }
        setMarked(false, hardwareID: display.hardwareID)
        disconnectedByID[display.displayID] = nil
        return nil
    }

    /// Re-enables every disabled display the WindowServer still knows about (BetterDisplay-style
    /// "connect to all displays") and clears all persisted disconnect state. This is the recovery
    /// path for a display turned off in a previous session that vanished from the public online list.
    ///
    /// Idempotent: if everything is already on, it simply clears any stale persisted off-state and
    /// reports success — "turn everything on" is a no-op success, never an error. Returns nil on
    /// success, else a user-facing error string (only when the OS API is unavailable).
    @discardableResult
    func connectAll() -> String? {
        guard isAvailable else { return "This macOS version doesn't expose the display on/off API" }
        let ids = CGSDisplayService.allKnownDisplayIDs()
        guard !ids.isEmpty else { return "Couldn't enumerate displays on this macOS version" }

        for id in ids where CGDisplayIsActive(id) == 0 {
            // A disabled real display keeps its EDID identity in this list (verified: vendor/model
            // stay non-zero when off). Skip the WindowServer's all-zero placeholder slot so we never
            // try to bring a phantom display online.
            let isPhantom = CGDisplayVendorNumber(id) == 0
                && CGDisplayModelNumber(id) == 0
                && CGDisplaySerialNumber(id) == 0
            guard !isPhantom else { continue }
            if CGSDisplayService.setDisplayEnabled(true, for: id) {
                disconnectedByID[id] = nil
            }
        }
        // Clear every persisted off-state (including stale "ghost" keys that no longer match a live
        // display) — the user asked for everything on.
        for hwID in persistedDisconnectedIDs() { setMarked(false, hardwareID: hwID) }
        disconnectedByID.removeAll()

        return nil
    }

    // MARK: - Restore on launch / wake

    /// Re-applies persisted disconnect state across `displays`, honoring the safety guards:
    /// never drops active count to 0, and only re-disconnects the built-in display when at least
    /// one external display is currently active. Call BEFORE the brightness/gamma reapply chain.
    func restoreAll(displays: [DisplayInfo]) {
        let hasActiveExternal = displays.contains { !$0.isBuiltin && CGDisplayIsActive($0.displayID) != 0 }
        for display in displays where isMarkedDisconnected(hardwareID: display.hardwareID) {
            // Built-in conditional restore: only re-disconnect if an external screen remains.
            if display.isBuiltin && !hasActiveExternal { continue }
            // Last-display guard.
            guard activeDisplayCount() > 1 else { continue }
            // Skip if already inactive.
            guard CGDisplayIsActive(display.displayID) != 0 else { continue }
            if CGSDisplayService.setDisplayEnabled(false, for: display.displayID) {
                disconnectedByID[display.displayID] = display.hardwareID
            }
        }
    }
}
