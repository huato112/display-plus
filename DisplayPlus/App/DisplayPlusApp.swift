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
                    // Enable "external above built-in" arrangement by default on first launch.
                    let defaults = UserDefaults.standard
                    if defaults.object(forKey: "fd.arrangement.externalAbove") == nil {
                        defaults.set(true, forKey: "fd.arrangement.externalAbove")
                    }

                    // After a 2-second delay (allows displays to fully initialize),
                    // position any external display above the built-in display.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        displayManager.arrangeExternalAboveBuiltin()
                    }

                    // Restore persisted display-disconnect state on launch (guarded against
                    // leaving zero usable screens). Runs after displays have enumerated.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        DisplayConnectionService.shared.restoreAll(displays: displayManager.displays)
                        displayManager.refreshDisplays()
                    }

                    // Wire up the wake-from-sleep handler so AppDelegate can call back
                    // into the live DisplayManager instance.
                    appDelegate.onWake = { [weak displayManager] in
                        guard let dm = displayManager else { return }
                        Task { @MainActor in
                            // Give WindowServer 2 seconds to stabilize after wake before
                            // touching display state.
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            dm.refreshDisplays()
                            // Re-apply persisted disconnect state FIRST — it changes which displays
                            // are active, so it must run before the brightness/gamma reapply below.
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            DisplayConnectionService.shared.restoreAll(displays: dm.displays)
                            dm.refreshDisplays()
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            for display in dm.displays {
                                // Apply software brightness factor first so GammaService
                                // can read the up-to-date factor when it re-applies its formula.
                                BrightnessService.shared.reapplySoftwareBrightnessIfNeeded(for: display)
                                GammaService.shared.reapplyIfNeeded(for: display.displayID)
                                // Re-apply any custom resolution that macOS may have reset on wake
                                ResolutionService.shared.reapplySavedModeIfNeeded(for: display.displayID)
                                // Re-activate HiDPI if the user enabled it and macOS reverted the mode
                                let (nW, nH) = display.nativeResolution
                                HiDPIService.shared.reapplyIfNeeded(for: display.displayID,
                                                                    uuid: display.displayUUID,
                                                                    nativeWidth: nW, nativeHeight: nH)
                            }
                        }
                    }
                }
        } label: {
            // SF Symbol name "display" retained here only as the documented fallback reference; the bundled MenuBarIcon template asset auto-tints to the menu-bar appearance.
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)
    }
}
