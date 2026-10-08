# Display+

A small macOS menu bar app for display power, HiDPI scaling and resolution selection.

## Features

- Turn built-in and external displays off or on directly from their switches.
- Keep displays turned off in the list so they can be switched back on.
- Recover displays turned off in a previous session with **Connect all displays**.
- Select HiDPI scaling, resolution and refresh rate.
- Restore saved display connection and mode preferences after sleep/wake.
- Prevent turning off the last active display.

Requires macOS 14 or later. Swift 6, SwiftUI and CoreGraphics, with no third-party dependencies.
HiDPI and display power use dynamically resolved private SkyLight APIs; availability depends on macOS.

## Build and install

Install Xcode and XcodeGen once:

```bash
brew install xcodegen
```

Run one command to generate the Xcode project, build Release, install the app in
`/Applications`, and launch it:

```bash
./build.sh
```

The script works from any working directory and signs the app locally without an
Apple Developer account. Build failures leave the installed app in place; the
full build log is saved to `build/build.log`. If `/Applications` requires
administrator access, the script asks for your password during installation.

To also create `build/DisplayPlus.dmg`, run `./build.sh --dmg`.
To install without launching, run `./build.sh --no-launch`.

For a compile check:

```bash
xcodebuild -scheme DisplayPlus -configuration Debug build
```

The app runs in the menu bar. It does not require Accessibility or Screen Recording permission.

## Source layout

- `App/`: menu bar entry point and wake notifications.
- `Models/`: display identity, connection state and display modes.
- `Services/`: enumeration, connection control, HiDPI and resolution switching.
- `Views/`: display rows, power switches, HiDPI scaling and mode selection.
- `DesignSystem/`: shared colors, spacing and cards.

`./build.sh` automatically regenerates the project after changes to source files
or `project.yml`. For manual Xcode builds, run `xcodegen generate` first.
Display power and mode switching need manual verification on real displays.
The documents under `docs/superpowers/` describe earlier versions of the app.
