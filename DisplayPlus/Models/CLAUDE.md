# Models

- `DisplayInfo.swift`: observable display identity, connection flags and available/current modes.
- `DisplayMode.swift`: logical/pixel resolution, refresh rate and HiDPI flag.

`hardwareID` captures vendor/model/serial at creation and remains stable across on/off.
`displayUUID` is used by HiDPI preferences but may be unavailable while a display is disabled.
`nativeResolution` supplies the native dimensions for HiDPI selection.
Update all consumers when changing DisplayInfo properties.
