# Views — SwiftUI View Layer

> Pure presentation and interaction. No business logic in Views; Views do not call Services directly.

## Structure

- **MenuBarView.swift** — main menu-bar view, the entry-point container for all features
- **DisplayDetailView.swift** — per-display expanded panel, a container of collapsible Sections
- Each Section corresponds to a dedicated View file (BrightnessSliderView, ColorProfileView, etc.)

## File List

| File | Purpose |
|------|---------|
| MenuBarView.swift | Menu-bar main view + all Section entry points |
| DisplayDetailView.swift | Display expanded panel (12 Sections) |
| BrightnessSliderView.swift | Brightness / contrast sliders |
| ResolutionSliderView.swift | Resolution slider |
| DisplayModeListView.swift | Resolution mode list (favorites pinned to top) |
| ArrangementView.swift | Display arrangement (with internal/external thumbnail distinction) |
| ColorProfileView.swift | ICC Profile selection |
| SystemColorView.swift | System color configuration |
| ImageAdjustmentView.swift | Image adjustments (gamma / contrast) |
| VirtualDisplayView.swift | HiDPI virtual display |
| NotchView.swift | Notch overlay |
| MainDisplayView.swift | Main display settings |
| AutoBrightnessView.swift | Ambient-light auto-brightness |

## Key Patterns

- `@EnvironmentObject var displayManager: DisplayManager` — global injection
- `@ObservedObject` for shared singletons (do NOT wrap `.shared` in `@StateObject`)
- Row components that need hover/loading state → extract as a standalone `struct` (do NOT use `@ViewBuilder` functions)
- Component naming: reusable rows are `XxxRow` or `XxxRowView`
- Unified hover effect: `.background(isHovered ? Color.primary.opacity(0.07) : .clear)`

## Change Checklist

- Adding a Section → update DisplayDetailView.swift and check MenuBarView layout
- Adding a tool entry point → update the tools area in MenuBarView.swift
- Adding a row component → must be a standalone struct, not a @ViewBuilder function
