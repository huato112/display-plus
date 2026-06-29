# DisplayPlus — Claude context

> A free, open-source alternative to BetterDisplay. macOS menu-bar app for managing displays:
> DDC brightness/contrast, resolution/HiDPI, display arrangement, color management, virtual displays.
> Swift 6 + SwiftUI (MenuBarExtra) + IOKit + CoreGraphics. Zero third-party dependencies.

## Current focus

- **✅ HiDPI (shipped, BetterDisplay-parity)** — the real BetterDisplay trick turned out to be simple:
  macOS already keeps scaled HiDPI modes (backing > native) in the **private CGS table** but the
  **public API hides them**; you just **activate** one via `CGSConfigureDisplayMode`. No injection,
  no virtual display, no mirror, no plist, no admin. Implemented in `Services/CGSDisplayService.swift`
  (CGS wrapper) + `Services/HiDPIService.swift` (policy/persistence). Mechanism + 212-byte descriptor
  layout: 👉 **`docs/superpowers/specs/2026-06-21-hidpi-injection-design.md`** (read the top "ข้อสรุปสุดท้าย").
  - **Phase B done:** expandable **scaling picker** in `HiDPIView` (`HiDPIService.scaleOptions` /
    `applyScale` / `currentScale`) lists every hidden HiDPI "looks like" res; per-scale persistence
    (`fd.hidpi.scale.<uuid>`) so the exact scale is restored on wake/reconnect; **presets** drive
    HiDPI through the CGS path (`PresetService` → `applyScale`, plain entries `clearPreference`).
  - **Phase C done:** the main **`DisplayModeListView`** now merges the hidden CGS HiDPI scales with
    the public 1× modes into one unified list (private `UnifiedMode`), with a per-resolution
    **refresh-rate** picker. Tap routing stays type-correct: public modes → `ResolutionService`,
    hidden HiDPI scales → `HiDPIService.applyMode` (persists scale/preference). Helpers:
    `HiDPIService.hiDPIModeOptions` (all HiDPI modes, per-refresh, no dedup) + `applyMode(number:…)`.
    `HiDPIView` stays as the prominent quick on/off + scale toggle.
- **Display disconnect (per-display on/off, BetterDisplay-style)** — `CGSConfigureDisplayEnabled`
  (private SkyLight) toggles a display in/out of the desktop. Mechanism in
  `Services/CGSDisplayService.swift` (`setDisplayEnabled`), policy/guards/persistence in
  `Services/DisplayConnectionService.swift`. UI: per-display "Connected" toggle in
  `DisplayDetailView` + a "Disconnected" section in `MenuBarView`. Persists
  (`fd.display.disconnected.<uuid>`), guarded so it never boots to a black screen. Spec:
  `docs/superpowers/specs/2026-06-21-display-disconnect-design.md`. ⚠️ Hardware verification of the
  private symbol pending (see plan's final section).
- Engineering gotchas (DDC, gamma, **CGS HiDPI**, private APIs, Swift 6, build): **`docs/ENGINEERING-NOTES.md`**.

## Stack & layout

- **Language**: Swift 6.0 (`SWIFT_STRICT_CONCURRENCY: minimal`). **Min OS**: macOS 14.0. Target hardware in use: M5 / macOS 27.
- **Architecture**: MVVM — `Views/` → `ViewModels/` → `Services/` → `Models/`.
- **Build**: XcodeGen (`project.yml`) + xcodebuild. No Sandbox (DDC/IOKit need it). No third-party deps.
- `Services/` = all system-framework work (IOKit/CoreGraphics/DDC). `Views/` = SwiftUI (`XxxView.swift` / `XxxRow.swift`).

## Build & verify (run after every change)

```bash
# Compile (the repo lives at ~/Documents/repo/display-plus)
cd ~/Documents/repo/display-plus && xcodebuild -scheme DisplayPlus -configuration Debug build 2>&1 | tail -20

# Regenerate xcodeproj — REQUIRED after adding/removing source files or editing project.yml
xcodegen generate

# Release build + DMG
./build.sh
```

There is no automated test suite (hardware-dependent). DDC/HiDPI changes must be verified on a real external display.

## Hard rules

- **Private framework symbols → `dlopen` + `dlsym`**, never `@_silgen_name` (link error).
- **Gamma table has one owner: `GammaService`.** Never call `CGSetDisplayTransferByFormula/Table` elsewhere; software brightness goes through GammaService. Reset one display with `GammaService.resetSingleDisplay(id)`, never global `CGDisplayRestoreColorSyncSettings()`.
- **DDC on Apple Silicon = `IOAVService`**, not the dead IOFramebuffer I2C API.
- **Display names = `NSScreen.localizedName`**; don't match IOKit by `CGDisplayVendorNumber/ModelNumber`.
- **UserDefaults keys must start with `fd.`**
- **C callbacks → `Unmanaged.passRetained(self)`** + paired `release()`; never `passUnretained`.
- **Services that write display hardware state (gamma, software brightness) must reapply on `NSWorkspace.didWakeNotification`** (BrightnessService before GammaService).
- View layer must not call CoreGraphics/IOKit directly.
- Row components needing `@State` must be standalone `struct`s, not `@ViewBuilder` funcs.
- After changing `DisplayInfo` properties, grep and update all references.

## Stop and ask the user

- Using a **new private API** (CoreDisplay/SkyLight/IOMobileFramebuffer, etc.).
- Anything needing **SIP disabled** or special system privileges.
- Architecture-direction changes (e.g. moving away from MVVM).

## Self-maintenance

- New durable gotcha → add to `docs/ENGINEERING-NOTES.md`.
- Keep this file lean; deep design lives in `docs/superpowers/specs/`.
