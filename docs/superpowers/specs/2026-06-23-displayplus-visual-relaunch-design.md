# DisplayPlus — Visual Relaunch (Design Spec)

- **Date:** 2026-06-23
- **Status:** Approved (2026-06-23) — ready for implementation planning
- **Scope:** A full **visual identity** overhaul so the app no longer resembles the cloned
  template/demo: new app icon, a vivid violet brand applied app-wide, card-based menu grouping, and
  removal of leftover original-template traces. **No** feature changes, **no** information-architecture
  changes (same sections, same order).

> TL;DR (TH): ทำให้ DisplayPlus "ไม่เหมือนเดมิเดิม" — icon ใหม่ (monogram **D+** บนพื้น
> indigo→violet gradient), เดินสีแบรนด์ **violet** ทั่วแอป (รวม tint toggle/slider), จัดเมนูเป็น
> **card grouping**, และเก็บกวาดร่องรอยต้นฉบับ (อักษรจีน, `com.freedisplay.*`). ฟีเจอร์/โครงเมนูเท่าเดิม.

---

## 1. Background & Motivation

The earlier rebrand spec (`2026-06-22-displayplus-rebrand-redesign-design.md`) renamed `FreeDisplay`
→ `DisplayPlus` and densified the menu (already shipped: `DisplayPlus/` folder, `Theme.swift` with
compact tokens). It deliberately **kept the original icon** and **respected the native blue accent**.

The remaining problem is **visual identity**: the app still looks like the open-source template it
was cloned from — a generic monitor-on-blue-gradient app icon, a system-blue accent, a flat
divider-separated list, and leftover Chinese dev docs / `com.freedisplay.*` identifiers. The user
wants a distinct, owned look.

This spec covers that identity pass only. It does not change what the app does.

## 2. Goals

- Replace the app icon with a distinct **"D+" monogram** mark on an indigo→violet gradient.
- Establish a **brand color** (indigo→violet) and route it through a single token so the whole UI —
  icon chips, badges, active affordances, **and native toggles/sliders** — reads violet, not blue.
- Reorganize the menu into **card groups** with section headers (no IA / feature change).
- Remove every remaining trace of the original template (Chinese strings/docs, `com.freedisplay.*`
  identifiers, stale path references).
- Keep the design **native-respecting**: still honors light/dark and system materials; the brand is
  expressed through accent + grouping, not a hardcoded dark skin.

## 3. Non-Goals (YAGNI)

- **No new features, no feature removal.** Every current control stays, in the same place.
- **No information-architecture change.** Same sections, same order; "card grouping" is a visual
  treatment over the existing structure, not a re-flow.
- **No persistence schema change.** UserDefaults keys keep the `fd.` prefix.
- **No migration code.** (The bundle-id/persistence reset was already accepted in the prior rebrand.)
- **No densify rework.** The compact metrics from the prior spec stay; cards wrap them.

## 4. Design Decisions

### 4.1 Brand color & tokens (`DisplayPlus/DesignSystem/Theme.swift`)

The brand is **indigo → violet**. One gradient, one solid accent derived from it.

| Token | Value | Use |
|---|---|---|
| `brandStart` | `#5B5BD6` (indigo) | gradient origin (top-leading) |
| `brandEnd` | `#7C4DFF` (violet) | gradient end (bottom-trailing) |
| `brandGradient` | `LinearGradient(brandStart→brandEnd, topLeading→bottomTrailing)` | icon chips that want depth, badges |
| `accent` | `~#6A5AE0` (solid mid-violet) | **replaces `.blue`** everywhere: chips, "Main" badge, active/link affordances |
| `controlTint` | `accent` | applied to native `Toggle`/`Slider` via `.tint(_:)` |

- **Native controls get `.tint(Theme.accent)`** so the system-blue switches/sliders become violet.
  This is the single biggest "not the demo" signal. (Decision confirmed 2026-06-23.)
- **Semantic colors are preserved only where they carry meaning:** Auto-Brightness sun = amber,
  "update available" = green, destructive Quit hover = red. Every other previously-blue chip → `accent`.
- All new color/spacing values live in `Theme`; **no new hardcoded literals** in views.

### 4.2 Card grouping tokens & components

Two new reusable components plus tokens, layered over the existing dense rows:

- **`SectionHeader`** — an uppercase caption (`.caption2`, semibold, `Theme.secondaryText`) with
  consistent leading/top padding. Renders group titles: `DISPLAYS`, `PRESETS`, `ARRANGE`,
  `BRIGHTNESS`, `TOOLS`, `SETTINGS`.
- **`Card`** — a rounded container (`RoundedRectangle(cornerRadius: Theme.cardCornerRadius)`) with
  `Theme.cardFill` background and `Theme.cardInset` horizontal inset, holding a group's rows. Replaces
  the hairline `Divider().opacity(0.3)` separators.
- **New tokens:** `cardCornerRadius` (~10), `cardInset` (~8, the horizontal margin so cards float off
  the popover edge), `cardContentVPadding`, `cardFill` (a subtle fill over the popover material —
  `Color.primary.opacity(~0.04)` or a thin material), `cardSpacing` (gap between cards).

The popover stays **340pt wide**, keeps its single `ScrollView`, and keeps the adaptive
`popoverMaxHeight` from the prior spec. The footer (version + Quit) stays fixed below the scroll.

### 4.3 Menu layout mapping (current → cards)

Same content, regrouped. `MenuBarView` body becomes a vertical stack of `Card`s, each preceded by a
`SectionHeader`:

| Card / header | Contents (unchanged) | Condition |
|---|---|---|
| `DISPLAYS` | `DisplayRowView` + expanded `DisplayDetailView` per display; `ConnectAllDisplaysRow` | always |
| `PRESETS` | `PresetListView` | always |
| `ARRANGE` | `Arrange Displays` `ExpandableRow` + `ArrangementView` | `visibleDisplays.count > 1` |
| `BRIGHTNESS` | `CombinedBrightnessView` | `settings.showCombinedBrightness` |
| `TOOLS` | `Virtual Displays` + `Auto Brightness` expandable rows + their panels | always |
| `SETTINGS` | `Settings` `ExpandableRow` + `SettingsView`; update banner | always |
| (footer, not a card) | `Display+ v…` + Quit | always, outside scroll |

Expand/collapse behavior, the unified display list, and the disconnect toggle are untouched.

### 4.4 App icon — "D+" monogram

- **Rewrite `scripts/generate-icon.py`** (PIL) to render: a squircle, an indigo→violet diagonal
  gradient fill, and a bold white **"D+"** wordmark — `D` as the dominant glyph with a smaller `+`
  raised toward the top-right. Subtle inner highlight for depth (matches the "Bold brand" direction).
- Generate every required size and **overwrite** `DisplayPlus/Assets.xcassets/AppIcon.appiconset/
  icon_{16,32,64,128,256,512,1024}.png`. Mirror into `scripts/icon_*.png` if those are the source set.
- The corner rounding is **baked into the PNG** (as today), so `Contents.json` is unchanged.

### 4.5 Menu-bar status glyph

- Replace `Image(systemName: "display")` in `DisplayPlusApp.swift` with a **custom monochrome
  template** "D+" mark rendered for the status bar (template image → tints to match the menu-bar
  appearance, light/dark/“reduce transparency” safe).
- **Fallback:** if the template asset is unavailable, fall back to an SF Symbol so the menu-bar item
  never renders blank. The glyph must read clearly at ~18pt.

### 4.6 Trace removal (original-template cleanup)

Confirmed remaining traces (the rebrand handled the rest):

- **Chinese dev docs → English:** `DisplayPlus/Models/CLAUDE.md`, `DisplayPlus/Services/CLAUDE.md`,
  `DisplayPlus/Views/CLAUDE.md` (currently Chinese). Translate to English; keep the same guidance.
- **Chinese full-width colon** in the accessibility label at `MenuBarView.swift:481`
  (`"Display：\(display.name)…"`) → ASCII `": "`.
- **`com.freedisplay.*` dispatch-queue labels** → `com.displayplus.*`:
  `DDCService.swift:24` (`com.freedisplay.ddc`), `BrightnessService.swift:79` (`com.freedisplay.brightness`).
- **Stale references in `CLAUDE.md`:** the `~/Documents/repo/FreeDisplay` build-path note (lines 45–46)
  and the `FreeDisplay/` grep example in `Models/CLAUDE.md:20` → `DisplayPlus`.
- **`README.md:115` first-run note** mentions migrating from "FreeDisplay" — reword to not surface the
  old template name (it's a fresh app; the historical name isn't user-relevant).
- **Final sweep:** `grep -rin "freedisplay\|[一-龥]"` across tracked source/docs (excluding the
  historical `docs/superpowers/` spec/plan filenames) returns nothing user- or identifier-facing.

> Permission strings and `.swift`/`.yml` Chinese were already clean (verified 2026-06-23).

## 5. Affected Files (inventory)

- **`DisplayPlus/DesignSystem/Theme.swift`** — add brand + card tokens (§4.1, §4.2).
- **`DisplayPlus/Views/MenuBarView.swift`** — add `SectionHeader` + `Card`; wrap groups (§4.3);
  swap `.blue` chips → `Theme.accent`; tint toggles; fix line-481 colon.
- **Section/detail views** (`DisplayDetailView`, `PresetListView`, `ArrangementView`,
  `VirtualDisplayView`, `AutoBrightnessView`, `BrightnessSliderView`, `ResolutionSliderView`,
  `ColorProfileView`, etc.) — route hardcoded `.blue` and native control tints through `Theme`.
- **`DisplayPlus/App/DisplayPlusApp.swift`** — custom template menu-bar glyph (§4.5).
- **`scripts/generate-icon.py`** + `DisplayPlus/Assets.xcassets/AppIcon.appiconset/*` — new icon (§4.4).
- **`DDCService.swift`, `BrightnessService.swift`** — queue-label rename (§4.6).
- **Docs:** three `CLAUDE.md` translations, root `CLAUDE.md`, `README.md` (§4.6).
- **`DisplayPlus.xcodeproj/project.pbxproj`** — regenerated by `xcodegen generate` if any file is
  added (e.g. a menu-bar glyph asset); not hand-edited.

## 6. Phasing (implementation order)

Each phase ends with a successful `xcodebuild` (and `xcodegen generate` after any file add or
`project.yml`/asset change). Visual results are confirmed by launching the app; DDC/HiDPI behavior is
unaffected but smoke-tested once at the end on the real external display.

1. **Brand tokens** — add brand + card tokens to `Theme.swift`. No view change yet (compiles, unused
   tokens are fine).
2. **App icon + menu-bar glyph** — rewrite `generate-icon.py`, regenerate assets, swap the status
   glyph. App shows the new D+ icon in Finder/Dock and a D+ glyph in the menu bar.
3. **Card layout** — add `SectionHeader` + `Card`; regroup `MenuBarView` per §4.3. Same content,
   grouped.
4. **Brand accent app-wide** — route every `.blue` chip/badge/link → `Theme.accent`; tint native
   toggles/sliders; keep the semantic exceptions. The UI reads violet.
5. **Trace removal + verify** — §4.6 cleanups, final grep sweep, build, launch, and a hardware
   smoke test (brightness/HiDPI/disconnect still work).

## 7. Risks & Caveats

- **PIL availability.** `generate-icon.py` needs Pillow. If unavailable, install into a venv or
  generate via an alternative (e.g. `sips`/Core Image) — resolve during Phase 2; do not block the
  rest. Output must be crisp at 16pt and 1024pt.
- **Menu-bar template legibility.** A "D+" at ~18pt monochrome can get muddy. If it doesn't read
  cleanly, simplify the glyph (e.g. a bolder single-weight mark) rather than shipping something
  illegible; SF Symbol fallback covers the failure case.
- **Card fill vs. popover material.** Too-strong a `cardFill` fights the system material and looks
  heavy. Keep it subtle (low-opacity primary fill or a thin material); verify in both light and dark.
- **Native tint scope.** `.tint(Theme.accent)` must be applied where the controls are (or high enough
  in the hierarchy) without bleeding into places that should stay semantic (e.g. the green update
  banner button). Apply per-control or per-group, not one blanket app-level tint.
- **No automated tests.** Build compiles are the automated gate; final behavior is verified manually
  on real hardware (DDC/HiDPI/disconnect).

## 8. Success Criteria

- Finder/Dock show the **D+ violet** icon; the menu bar shows a **D+** glyph (not the generic monitor).
- The popover reads **violet**: chips, badges, active states, **and toggles/sliders** are violet, not
  blue; semantic amber/green/red remain only where meaningful.
- The menu is visibly **grouped into cards** with section headers; all current features remain in the
  same place and order.
- `grep -rin "freedisplay"` and a CJK sweep over tracked source/docs (excluding historical
  `docs/superpowers/` filenames) return nothing user- or identifier-facing.
- All new styling values come from `Theme.swift`; no new hardcoded color/spacing literals in views.
- DDC brightness, HiDPI scaling, and per-display disconnect still work on real hardware.

## 9. Resolved vs. Open

- **Resolved:** scope = icon + brand + card layout + trace removal; aesthetic = Bold brand (vivid);
  brand = indigo→violet (`#5B5BD6`→`#7C4DFF`), solid accent `~#6A5AE0`; icon mark = **D+** monogram;
  menu-bar glyph = custom **D+** template with SF Symbol fallback; layout = **card grouping** (no IA
  change); **native toggles/sliders tinted violet** (confirmed); semantic colors kept only for
  amber/green/red meanings; `fd.` keys unchanged; width stays 340pt.
- **Open:** none. Spec approved 2026-06-23.
