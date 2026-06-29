# Models — Data Model Layer

> Pure data structures; ObservableObject.

## Files

| File | Purpose |
|------|---------|
| DisplayInfo.swift | State model for a single display (high risk) |
| DisplayMode.swift | Display-mode value type (resolution + refresh rate + HiDPI) |

---

## DisplayInfo.swift — High Risk

Core display model with multiple `@Published` properties. **All Views and Services depend on this class.**

### Change Protocol

1. Adding or removing a `@Published` property → `grep -r "DisplayInfo" DisplayPlus/ --include="*.swift"` to find all references
2. Update every reference point in sync (build passing ≠ logic correct)
3. `loadDetails()` is an async method; it is called on new displays inside `DisplayManager.refreshDisplays()`

### Key Property Notes

- `displayID: CGDirectDisplayID` — hardware identifier; may change after a hot-plug (do not use as a persistent key)
- `isBuiltin` — determined with `CGDisplayIsBuiltin()`
- `bounds` — from `CGDisplayBounds()`; must be refreshed after hot-plug or arrangement changes
- `name` — from `NSScreen.localizedName` (more reliable than IOKit vendorID/modelNumber)
- `rotation` property was removed in Phase 21 (removed together with RotationService/RotationView)

---

## DisplayMode.swift

Value type for a single display mode (resolution + refresh rate + HiDPI flag).

- `currentMode(for:)` static method retrieves the current mode
- `availableModes(for:)` retrieves the list of available modes (including HiDPI variants)
- Changes affect ResolutionService and DisplayModeListView

### HiDPI Notes

- HiDPI modes are distinguished by the `kIOScalingModeKey` flag, not simply by 2× resolution
- HiDPI modes for virtual displays are dynamically injected by VirtualDisplayService, not sourced from DisplayMode
