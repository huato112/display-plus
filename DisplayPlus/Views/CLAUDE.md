# Views

- `MenuBarView.swift`: display list, expansion, on/off switches, reconnect recovery and Quit.
- `DisplayDetailView.swift`: HiDPI and resolution sections.
- `HiDPIView.swift`: external display scaling picker.
- `DisplayModeListView.swift`: public and hidden HiDPI modes with refresh rates.

The list includes disabled displays so users can reconnect them.
Use standalone structs for stateful rows and shared Theme tokens for styling.
Views call service APIs instead of CoreGraphics directly.
