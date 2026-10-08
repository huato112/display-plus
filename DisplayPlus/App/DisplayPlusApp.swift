import SwiftUI

@main
struct DisplayPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var displayManager = DisplayManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(displayManager)
                .task {
                    // Wait for display enumeration before restoring saved connection state.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        DisplayConnectionService.shared.restoreAll(displays: displayManager.displays)
                        displayManager.refreshDisplays()
                    }

                    appDelegate.onWake = { [weak displayManager] in
                        guard let manager = displayManager else { return }
                        Task { @MainActor in
                            // Give WindowServer time to settle after wake.
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            manager.refreshDisplays()
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            DisplayConnectionService.shared.restoreAll(displays: manager.displays)
                            manager.refreshDisplays()
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            for display in manager.displays where display.isEnabled {
                                ResolutionService.shared.reapplySavedModeIfNeeded(for: display.displayID)
                                let (width, height) = display.nativeResolution
                                HiDPIService.shared.reapplyIfNeeded(
                                    for: display.displayID, uuid: display.displayUUID,
                                    nativeWidth: width, nativeHeight: height)
                            }
                        }
                    }
                }
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)
    }
}
