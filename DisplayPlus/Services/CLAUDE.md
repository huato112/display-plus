# Services — Business Logic Layer

> System-framework interaction layer; no UI. All Services are `@MainActor` singletons (`static let shared`).

## Responsibilities

Interact directly with macOS system frameworks (IOKit, CoreGraphics, ScreenCaptureKit, ColorSync)
and expose high-level APIs to Views/ViewModels.

## Key Patterns

- **Singleton + @MainActor**: All Services are marked `@MainActor final class: ObservableObject, @unchecked Sendable`
- **DDC communication**: DDCService is the low-level dependency for all external display features; Apple Silicon uses IOAVService
- **Gamma table sole writer**: GammaService owns all writes to `CGSetDisplayTransfer*`
  - BrightnessService's software brightness writes through GammaService indirectly
  - No other Service or View should call `CGSetDisplayTransferByFormula/Table` directly
- **CGHelpers.runWithTimeout**: blocking CG calls (apply settings, enableMirror) must be wrapped with this helper

## File List

| File | Purpose |
|------|---------|
| DDCService.swift | IOKit I2C / IOAVService DDC communication layer |
| DisplayManager.swift | Display enumeration, refresh, cross-Service coordination |
| BrightnessService.swift | Software brightness (written through GammaService) |
| GammaService.swift | Gamma table sole writer |
| AutoBrightnessService.swift | Sync external display brightness to built-in screen (CoreDisplay API) |
| ResolutionService.swift | Resolution / HiDPI mode switching |
| ArrangementService.swift | Display arrangement |
| MirrorService.swift | Mirror mode |
| HiDPIService.swift | HiDPI detection and management |
| VirtualDisplayService.swift | CGVirtualDisplay creation / destruction |
| ColorProfileService.swift | ColorSync ICC Profile |
| NotchOverlayManager.swift | Notch overlay layer |
| SettingsService.swift | UserDefaults persistence |
| UpdateService.swift | App update detection |
| LaunchService.swift | Launch at login |
| CGHelpers.swift | CG blocking-call timeout wrapper |

## Cross-Service Rules

- **Sleep/wake reapply order**: BrightnessService → GammaService (Brightness is the data provider for Gamma)
  - AppDelegate listens to `NSWorkspace.didWakeNotification` → calls reapply
- **C callbacks**: use `Unmanaged.passRetained(self)` + paired `release()`; never `passUnretained`
- **VirtualDisplayService**: HiDPI configuration is purely runtime (do NOT persist to UserDefaults autoCreate);
  `CGVirtualDisplay(descriptor:)` init must run on the main thread

## Testing Notes

- DDC/IOKit features must be tested manually on a real external display
- After VirtualDisplayService creates a display, verify `CGVirtualDisplay` is non-nil (vendorID must be non-zero)
