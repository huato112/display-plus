# Display+

> **Free & open-source alternative to [BetterDisplay](https://github.com/waydabber/BetterDisplay)** — all the core display management features, zero cost.

Display+ implements the most essential BetterDisplay features as a completely free, open-source macOS menu bar app.

[Download Latest Release](https://github.com/<your-username>/display-plus/releases/latest) | [Report an Issue](https://github.com/<your-username>/display-plus/issues)

> **Note:** The GitHub repository will be available at `https://github.com/<your-username>/display-plus` once the repo rename is complete (user action).

---

## What BetterDisplay Features Does This Replace?

| BetterDisplay Feature | Display+ | Notes |
|----------------------|:-----------:|-------|
| DDC Brightness & Contrast | ✅ | Hardware control via IOKit I2C (Intel) / IOAVService (Apple Silicon) |
| Software Brightness (Gamma) | ✅ | Per-display gamma table control with smooth transitions |
| Keyboard Brightness Keys for External Displays | ✅ | Intercepts brightness keys when cursor is on external display, shows native macOS OSD |
| Auto Brightness Sync | ✅ | Syncs external display brightness with built-in display changes |
| HiDPI Virtual Displays | ✅ | Activates hidden HiDPI modes via CGS private API (no virtual display required) |
| Display Arrangement | ✅ | Position displays (external above built-in, etc.) |
| Resolution & HiDPI Switching | ✅ | Browse and switch all available display modes including HiDPI |
| ICC Color Profile Management | ✅ | Switch color profiles per display via ColorSync |
| Image Adjustment (Gamma/Temperature) | ✅ | Software contrast, color temperature, RGB channels, invert |
| Display Presets | ✅ | Save & restore full display configurations with one click |
| Virtual Display (Dummy) | ✅ | Create headless virtual displays |
| Notch Management | ✅ | Hide the MacBook notch with a black overlay |
| Launch at Login | ✅ | Via SMAppService |

### Not Included (intentionally)

- Screen streaming / PiP — rarely used, adds complexity
- EDID override — requires SIP disabled
- XDR/HDR extra brightness — requires specific hardware

---

## Screenshots

*Coming soon*

---

## Installation

### Option 1: Download DMG

1. Download `DisplayPlus.dmg` from [Releases](https://github.com/<your-username>/display-plus/releases/latest)
2. Open the DMG and drag **Display+.app** to **Applications**
3. First launch: right-click → **Open** (unsigned app, one-time approval)

### Option 2: Build from Source

**Prerequisites:** Xcode (with Command Line Tools) + [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# One-time: install the project generator
brew install xcodegen

# Get the code
git clone https://github.com/<your-username>/display-plus.git
cd display-plus

# Generate DisplayPlus.xcodeproj from project.yml
# (re-run this whenever you add/remove source files or edit project.yml)
xcodegen generate
```

#### Build a release app + DMG, then install it

`build.sh` archives a **Release** build, exports a self-contained `.app`, and packages a `.dmg`:

```bash
./build.sh
# Output:
#   build/export/DisplayPlus.app   ← the app
#   build/DisplayPlus.dmg          ← the installer image
```

Install it into `/Applications` (this replaces any older copy):

```bash
# Quit the app first if it's running, then:
rm -rf /Applications/DisplayPlus.app
ditto build/export/DisplayPlus.app /Applications/DisplayPlus.app

# The app is unsigned. Clear the Gatekeeper quarantine flag so it opens
# directly (otherwise: first launch needs right-click → Open):
xattr -dr com.apple.quarantine /Applications/DisplayPlus.app

open /Applications/DisplayPlus.app
```

> Shows in Finder / the menu bar as **Display+**; the bundle on disk is `DisplayPlus.app`.

#### Quick iteration (Debug, no DMG)

For fast compile-check loops while developing, skip `build.sh` and build Debug directly:

```bash
xcodebuild -scheme DisplayPlus -configuration Debug build
```

---

## Permissions

| Permission | Why |
|------------|-----|
| **Accessibility** | Required for brightness key interception on external displays |

No internet connection required (except optional update checks via GitHub Releases API).

> **First-run note:** Display+ is a fresh app identity — on first launch you'll re-grant Accessibility (and Screen Recording if you use live preview), so presets and settings start clean.

---

## Tech Stack

- **Swift 6** + **SwiftUI** (MenuBarExtra)
- **IOKit** — DDC/CI I2C for hardware brightness/contrast
- **CoreGraphics** — Display enumeration, resolution, arrangement
- **ColorSync** — ICC color profile management
- **CGVirtualDisplay** — Virtual display creation (private API, macOS 14+)
- **CoreDisplay** — Built-in display brightness reading (private API, via dlopen)
- Zero third-party dependencies

---

## Project Structure

```
DisplayPlus/
├── App/              # AppDelegate, app entry point
├── Models/           # DisplayInfo, DisplayMode, DisplayPreset
├── Services/         # System-level services (DDC, brightness, resolution, gamma, etc.)
└── Views/            # SwiftUI views for each feature section
```

---

## How It Works

Display+ sits in your menu bar and talks directly to your displays:

- **External monitors**: Uses DDC/CI protocol over I2C (Intel) or IOAVService (Apple Silicon) to control hardware brightness, contrast, and other settings
- **Built-in display**: Uses CoreGraphics gamma tables for software brightness adjustment
- **Brightness keys**: Installs a CGEventTap to intercept keyboard brightness keys and route them to the display under your mouse cursor
- **Auto brightness**: Polls the built-in display brightness via CoreDisplay private API and proportionally adjusts external displays
- **HiDPI**: Activates hidden HiDPI modes already present in the private CGS table via `CGSConfigureDisplayMode` — no virtual display, no plist, no admin required

---

## Contributing

Issues and PRs welcome. This project uses:
- `xcodegen` for project generation (edit `project.yml`, not `.xcodeproj`)
- Swift 6 with `SWIFT_STRICT_CONCURRENCY: minimal`
- MVVM architecture (View → ViewModel → Service)

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Acknowledgments

- Inspired by [BetterDisplay](https://github.com/waydabber/BetterDisplay), [MonitorControl](https://github.com/MonitorControl/MonitorControl), and [Lunar](https://lunar.fyi/)
- CGVirtualDisplay bridging header based on [Chromium's virtual_display_mac_util.mm](https://chromium.googlesource.com/chromium/src/+/main/ui/display/mac/test/virtual_display_mac_util.mm)
