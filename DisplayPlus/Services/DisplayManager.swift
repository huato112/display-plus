import Foundation
import Combine
import CoreGraphics

// Global C-compatible callback for display reconfiguration.
// Must be a top-level function (not a closure) to be used as a C function pointer.
private func displayReconfigCallback(
    displayID: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let ptr = userInfo else { return }
    let manager = Unmanaged<DisplayManager>.fromOpaque(ptr).takeUnretainedValue()

    let relevant: CGDisplayChangeSummaryFlags = [.addFlag, .removeFlag, .setMainFlag, .setModeFlag]
    guard !flags.intersection(relevant).isEmpty else { return }

    // Skip the begin-configuration notification; only act when the change is complete.
    // (beginConfigurationFlag is set at the start of a transaction; absence means it finished.)
    guard !flags.contains(.beginConfigurationFlag) else { return }

    Task { @MainActor in
        if flags.intersection([.addFlag, .removeFlag]).isEmpty {
            // Mode or main-display change: refresh mode info for existing displays only.
            manager.refreshExistingDisplayModes()
        } else {
            manager.refreshDisplays()
        }
    }
}

@MainActor
class DisplayManager: ObservableObject {
    @Published var displays: [DisplayInfo] = []

    // nonisolated(unsafe) allows deinit (which is nonisolated in Swift 6) to access this value.
    nonisolated(unsafe) private var callbackContext: UnsafeMutableRawPointer?

    init() {
        refreshDisplays()
        setupReconfigCallback()
    }

    deinit {
        if let ctx = callbackContext {
            CGDisplayRemoveReconfigurationCallback(displayReconfigCallback, ctx)
            Unmanaged<DisplayManager>.fromOpaque(ctx).release()
        }
    }

    func refreshDisplays() {
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount)

        let currentIDs = Set(displays.map { $0.displayID })
        let newIDSet = Set((0..<Int(displayCount)).map { displayIDs[$0] })

        // Diff-based refresh: keep existing DisplayInfo objects (preserves @Published state)
        let existingByID = Dictionary(uniqueKeysWithValues: displays.map { ($0.displayID, $0) })

        var updatedDisplays: [DisplayInfo] = []
        var addedDisplays: [DisplayInfo] = []

        for i in 0..<Int(displayCount) {
            let id = displayIDs[i]
            if let existing = existingByID[id] {
                updatedDisplays.append(existing)
            } else {
                let info = DisplayInfo(displayID: id)
                updatedDisplays.append(info)
                addedDisplays.append(info)
            }
        }

        // Retain displays we disconnected that have dropped off the online list. A CGS-disconnected
        // display disappears from CGGetOnlineDisplayList entirely, so without this it would vanish
        // from the menu with no way to turn it back on. Keep its existing DisplayInfo (its
        // displayID stays valid for reconnect) and mark it inactive so its switch stays visible.
        let onlineIDs = Set(updatedDisplays.map { $0.displayID })
        for display in displays where !onlineIDs.contains(display.displayID)
            && DisplayConnectionService.shared.isDisconnected(displayID: display.displayID) {
            display.isEnabled = false
            display.isOnline = false
            updatedDisplays.append(display)
        }

        displays = updatedDisplays

        // Load resolution details and restore HiDPI for newly appeared displays.
        for display in addedDisplays {
            Task {
                await display.loadDetails()
                // Auto-enable HiDPI for new external 2K+ displays that don't have it yet
                if display.isEnabled && !display.isBuiltin {
                    await self.autoEnableHiDPIIfNeeded(for: display)
                }
            }

        }

        // Refresh connection state for displays that are still online.
        let keptIDs = currentIDs.intersection(newIDSet)
        for display in updatedDisplays where keptIDs.contains(display.displayID) {
            display.isMain = CGDisplayIsMain(display.displayID) != 0
            display.isEnabled = CGDisplayIsActive(display.displayID) != 0
            display.isOnline = CGDisplayIsOnline(display.displayID) != 0
        }
    }

    /// Applies the right HiDPI state for a freshly connected external display.
    ///
    /// - If the user has an explicit preference for this display, honor it (re-activate HiDPI if it
    ///   was on and macOS reverted the mode on reconnect).
    /// - Otherwise, on first sight, auto-enable HiDPI for 2K+ displays so crisp text "just works"
    ///   when switching monitors. The user can still turn it off; that choice is then remembered.
    private func autoEnableHiDPIIfNeeded(for display: DisplayInfo) async {
        let uuid = display.displayUUID
        let (nativeW, nativeH) = display.nativeResolution

        // Known display — respect the stored preference (re-apply if it drifted).
        if HiDPIService.shared.hasPreference(uuid: uuid) {
            HiDPIService.shared.reapplyIfNeeded(for: display.displayID, uuid: uuid,
                                                nativeWidth: nativeW, nativeHeight: nativeH)
            return
        }

        // First sight: only auto-enable for 2K+ displays, and only if not already HiDPI.
        guard nativeW >= 2560 || (nativeW * nativeH >= 2560 * 1440) else { return }
        guard !HiDPIService.shared.isHiDPIActive(for: display.displayID) else { return }

        print("[DisplayManager] Auto-enabling HiDPI for \(display.name) (\(nativeW)×\(nativeH))")
        let err = await HiDPIService.shared.enableHiDPI(
            for: display.displayID, uuid: uuid, nativeWidth: nativeW, nativeHeight: nativeH)

        if let err {
            print("[DisplayManager] Auto-enable HiDPI failed: \(err)")
        } else {
            print("[DisplayManager] Auto-enable HiDPI succeeded, refreshing modes")
            HiDPIService.shared.refreshModes(for: display)
            try? await Task.sleep(nanoseconds: 500_000_000)
            await display.loadDetails()
        }
    }

    private func setupReconfigCallback() {
        let ctx = Unmanaged.passRetained(self).toOpaque()
        callbackContext = ctx
        CGDisplayRegisterReconfigurationCallback(displayReconfigCallback, ctx)
    }

    /// Refreshes mode info and main-display flag for already-tracked displays
    /// (for setModeFlag / setMainFlag events).
    /// Cheaper than a full `refreshDisplays()` — does not add/remove DisplayInfo objects.
    func refreshExistingDisplayModes() {
        for display in displays {
            // Always refresh isMain synchronously since it's cheap and needed for setMainFlag events.
            display.isMain = CGDisplayIsMain(display.displayID) != 0
            Task {
                let newMode = await Task.detached(priority: .userInitiated) {
                    DisplayMode.currentMode(for: display.displayID)
                }.value
                display.currentDisplayMode = newMode
            }
        }
    }

    /// Connects or disconnects a display from the desktop arrangement (disconnect = BetterDisplay-style
    /// "turn off"). Returns nil on success, or a user-facing error string. Refreshes the display list
    /// shortly after so the UI reflects the new active/online state.
    @discardableResult
    func setConnected(_ connected: Bool, for display: DisplayInfo) -> String? {
        let err = connected
            ? DisplayConnectionService.shared.reconnect(display)
            : DisplayConnectionService.shared.disconnect(display)
        if err == nil {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                self.refreshDisplays()
            }
        }
        return err
    }

    /// Re-enables every disabled display (BetterDisplay-style "connect to all displays") — the
    /// recovery path for a display turned off in a previous session that dropped off the online list.
    /// Returns nil on success, else a user-facing error string. Refreshes shortly after.
    @discardableResult
    func connectAllDisplays() -> String? {
        let err = DisplayConnectionService.shared.connectAll()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            self.refreshDisplays()
        }
        return err
    }

}
