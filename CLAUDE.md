# DisplayPlus

A focused macOS menu bar app: display on/off, HiDPI scaling, and resolution/refresh rate selection.
Swift 6 + SwiftUI + CoreGraphics. macOS 14+, no third-party dependencies.

## Scope

Only display connection, HiDPI, and resolution features belong in this app.
Built-in and external display power switches behave identically, without confirmation.
Displays disabled by the app remain listed so the same switch can reconnect them.
A recovery row reconnects displays disabled in a previous session.

## Implementation

- `DisplayManager`: display enumeration, reconfiguration callbacks and HiDPI restore.
- `DisplayConnectionService`: power state, persistence, last-active-display guard and recovery.
- `CGSDisplayService`: dynamic SkyLight symbol loading and display configuration transactions.
- `HiDPIService`: scaled modes, preferences and wake/reconnect restore.
- `ResolutionService`: public mode switching and shared CGS fallback.
- `CGHelpers`: timeout around blocking public CoreGraphics transactions.

## Rules

- Private symbols use `dlopen` + `dlsym`, never link-time extern declarations.
- CGS configuration transactions run on the main thread.
- C callbacks use `Unmanaged.passRetained(self)` with paired `release()`.
- UserDefaults keys start with `fd.`.
- Views call services instead of CoreGraphics directly.
- Stateful row components are standalone structs.
- DisplayInfo property changes require checking all remaining references.
- Mode restore only applies to enabled displays.

## Verification

After adding/removing source files or editing `project.yml`, run `xcodegen generate`.
Compile with `xcodebuild -scheme DisplayPlus -configuration Debug build`.
Use `./build.sh` for Release + DMG + installation to `/Applications`.
Verify power switches and mode changes on real displays.
The existing `docs/superpowers/` specs describe historical versions.

## Consult the user

New private APIs, SIP changes or special system privileges require explicit discussion.
