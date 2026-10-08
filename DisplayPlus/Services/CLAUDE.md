# Services

CoreGraphics/SkyLight interaction for display connection, HiDPI and resolution.

- `DisplayManager.swift`: enumerate and refresh displays; retain disconnected rows.
- `DisplayConnectionService.swift`: on/off, persistence, recovery and last-active-display guard.
- `CGSDisplayService.swift`: dynamic private symbols and configuration transactions.
- `HiDPIService.swift`: HiDPI modes, scaling preferences and restore.
- `ResolutionService.swift`: public resolution switching and shared CGS fallback.
- `CGHelpers.swift`: timeout for blocking public configuration calls.

CGS transactions run on the main thread. Private symbols use `dlopen` + `dlsym`.
C callbacks use retained contexts with paired release. Persistence keys start with `fd.`.
Restore display connection state before mode preferences; skip disabled displays for mode restore.
Hardware behavior requires testing with real displays.
