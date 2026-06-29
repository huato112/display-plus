import SwiftUI

/// Unified resolution list: public 1× modes **plus** the hidden CGS HiDPI ("Retina") scales that
/// macOS keeps out of `CGDisplayCopyAllDisplayModes`. Each resolution offers a refresh-rate picker.
/// Tapping a public mode routes through `ResolutionService`; a hidden HiDPI scale routes through
/// `HiDPIService` (the BetterDisplay CGS mechanism) — the view never touches CoreGraphics directly.
struct DisplayModeListView: View {
    @ObservedObject var display: DisplayInfo
    @State private var isSwitching: Bool = false
    @State private var flashModeID: Int32? = nil
    @State private var switchingModeID: Int32? = nil
    @State private var showAllModes: Bool = false
    @State private var errorMessage: String?

    /// The active mode's logical resolution + HiDPI flag, read from the live current mode.
    private var activeKey: ResolutionGroup.Key? {
        guard let m = display.currentDisplayMode else { return nil }
        return ResolutionGroup.Key(width: m.width, height: m.height, isHiDPI: m.isHiDPI)
    }

    /// The active refresh rate (Hz), used to highlight the current rate within a group.
    private var activeRefresh: Int? {
        guard let m = display.currentDisplayMode, m.refreshRate > 0 else { return nil }
        return Int(m.refreshRate.rounded())
    }

    // MARK: - Mode merge

    /// Public modes (1×, applied via ResolutionService) merged with the hidden CGS HiDPI scales
    /// (applied via HiDPIService). Deduplicated by mode number; public wins on a tie.
    private var unifiedModes: [UnifiedMode] {
        var items: [UnifiedMode] = display.availableModes
            .filter { $0.width >= 1280 && $0.height >= 720 }
            .map {
                UnifiedMode(number: $0.id, width: $0.width, height: $0.height,
                            refresh: $0.refreshRate > 0 ? Int($0.refreshRate.rounded()) : 0,
                            isHiDPI: $0.isHiDPI, publicMode: $0)
            }
        var seen = Set(items.map { $0.number })
        for o in HiDPIService.shared.hiDPIModeOptions(for: display.displayID) where !seen.contains(o.modeNumber) {
            seen.insert(o.modeNumber)
            items.append(UnifiedMode(number: o.modeNumber, width: o.width, height: o.height,
                                     refresh: o.refresh, isHiDPI: true, publicMode: nil))
        }
        return items
    }

    /// Group modes by (resolution + HiDPI), one entry per refresh rate, sorted by resolution descending.
    private var resolutionGroups: [ResolutionGroup] {
        var grouped: [ResolutionGroup.Key: [UnifiedMode]] = [:]
        for m in unifiedModes {
            grouped[ResolutionGroup.Key(width: m.width, height: m.height, isHiDPI: m.isHiDPI), default: []].append(m)
        }

        return grouped.map { (key, modes) in
            // One mode per refresh rate; prefer the public variant so the proven apply path is used.
            var byRefresh: [Int: UnifiedMode] = [:]
            for m in modes {
                if let existing = byRefresh[m.refresh], existing.publicMode != nil { continue }
                byRefresh[m.refresh] = m
            }
            let sorted = byRefresh.values.sorted { $0.refresh > $1.refresh }
            return ResolutionGroup(width: key.width, height: key.height, isHiDPI: key.isHiDPI, modes: sorted)
        }
        .sorted { lhs, rhs in
            if lhs.width != rhs.width { return lhs.width > rhs.width }
            if lhs.height != rhs.height { return lhs.height > rhs.height }
            if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI }
            return false
        }
    }

    /// Compact: show top 4 groups
    private var visibleGroups: [ResolutionGroup] {
        showAllModes ? resolutionGroups : Array(resolutionGroups.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Display Mode")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { HiDPIService.shared.refreshModes(for: display) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)
                .help("Refresh Mode List")
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)

            if resolutionGroups.isEmpty {
                Text("No available display modes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                // Resolution rows
                ForEach(visibleGroups) { group in
                    ResolutionRow(
                        group: group,
                        activeKey: activeKey,
                        activeRefresh: activeRefresh,
                        isSwitching: isSwitching,
                        switchingModeID: switchingModeID,
                        flashModeID: flashModeID,
                        onSelectMode: { switchTo($0) }
                    )
                }

                // Toggle button
                if resolutionGroups.count > 4 || showAllModes {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) { showAllModes.toggle() }
                    }) {
                        HStack(spacing: 4) {
                            Text(showAllModes ? "Collapse" : "Show all \(resolutionGroups.count)")
                                .font(.caption)
                                .foregroundColor(Theme.accent)
                            Image(systemName: showAllModes ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(Theme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                }
            }

            // Error message
            if let msg = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text(msg)
                        .font(.caption2)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.08))
                .cornerRadius(6)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Actions

    private func switchTo(_ mode: UnifiedMode) {
        guard !isSwitching else { return }

        // Already the active mode (same resolution + HiDPI + refresh) → just flash it.
        if let cur = display.currentDisplayMode,
           cur.width == mode.width, cur.height == mode.height, cur.isHiDPI == mode.isHiDPI,
           (mode.refresh == 0 || Int(cur.refreshRate.rounded()) == mode.refresh) {
            withAnimation(.easeInOut(duration: 0.15)) { flashModeID = mode.id }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation(.easeInOut(duration: 0.15)) { flashModeID = nil }
            }
            return
        }

        isSwitching = true
        switchingModeID = mode.id
        let displayID = display.displayID
        let uuid = display.displayUUID
        Task { @MainActor in
            var success: Bool
            if let publicMode = mode.publicMode {
                // Public mode → ResolutionService. A plain 1× pick must forget any HiDPI preference
                // so wake/reconnect reapply won't fight it back into HiDPI.
                if !mode.isHiDPI { HiDPIService.shared.clearPreference(uuid: uuid) }
                success = await ResolutionService.shared.setDisplayMode(publicMode, for: displayID)
                if !success {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    success = await ResolutionService.shared.setDisplayMode(publicMode, for: displayID)
                }
            } else {
                // Hidden CGS HiDPI scale → HiDPIService (sets preference + persists the scale).
                let err = await HiDPIService.shared.applyMode(
                    number: mode.number, width: mode.width, height: mode.height,
                    isHiDPI: mode.isHiDPI, for: displayID, uuid: uuid)
                success = (err == nil)
            }

            if success {
                try? await Task.sleep(nanoseconds: 300_000_000)
                let refreshed = await Task.detached(priority: .userInitiated) {
                    DisplayMode.currentMode(for: displayID)
                }.value
                display.currentDisplayMode = refreshed
                HiDPIService.shared.refreshModes(for: display)
                errorMessage = nil
            } else {
                withAnimation {
                    errorMessage = "Cannot switch to \(mode.width)×\(mode.height), please try again"
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation { errorMessage = nil }
                }
            }
            isSwitching = false
            switchingModeID = nil
        }
    }
}

// MARK: - Data model

/// A selectable mode in the unified list. Public 1× modes carry their `DisplayMode` (applied via
/// `ResolutionService`); the hidden CGS HiDPI scales carry only a mode number (applied via
/// `HiDPIService`). `number` is the shared `ioDisplayModeID` / CGS modeNum.
private struct UnifiedMode: Identifiable {
    let number: Int32
    let width: Int
    let height: Int
    let refresh: Int          // Hz (0 == display default)
    let isHiDPI: Bool
    let publicMode: DisplayMode?

    var id: Int32 { number }
    var refreshString: String { refresh > 0 ? "\(refresh)Hz" : "-- Hz" }
}

private struct ResolutionGroup: Identifiable {
    struct Key: Hashable {
        let width: Int
        let height: Int
        let isHiDPI: Bool
    }

    let width: Int
    let height: Int
    let isHiDPI: Bool
    let modes: [UnifiedMode] // sorted by refresh rate descending

    var id: String { "\(width)x\(height)_\(isHiDPI)" }
    var key: Key { Key(width: width, height: height, isHiDPI: isHiDPI) }
    var resolutionString: String { "\(width)×\(height)" }
    var hasMultipleRates: Bool { modes.count > 1 }
    var bestMode: UnifiedMode { modes[0] }
}

// MARK: - ResolutionRow

private struct ResolutionRow: View {
    let group: ResolutionGroup
    let activeKey: ResolutionGroup.Key?
    let activeRefresh: Int?
    let isSwitching: Bool
    let switchingModeID: Int32?
    let flashModeID: Int32?
    let onSelectMode: (UnifiedMode) -> Void

    @State private var isHovered = false
    @State private var showRates = false

    private var isCurrent: Bool {
        group.key == activeKey
    }

    private var isAnySwitching: Bool {
        group.modes.contains { $0.id == switchingModeID }
    }

    private var isFlashing: Bool {
        group.modes.contains { $0.id == flashModeID }
    }

    /// The active mode within this group (if this resolution is the current one).
    private var activeMode: UnifiedMode? {
        guard isCurrent else { return nil }
        if let r = activeRefresh, let m = group.modes.first(where: { $0.refresh == r }) { return m }
        return group.modes.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Resolution row
            HStack(spacing: 6) {
                if isAnySwitching {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                }

                Text(group.resolutionString)
                    .font(.caption)
                    .foregroundColor(isCurrent ? .primary : .secondary)
                    .monospacedDigit()

                if group.isHiDPI {
                    TagBadge(text: "HiDPI", color: Theme.accent)
                }

                // Show current refresh rate
                if let active = activeMode, active.refresh > 0 {
                    Text(active.refreshString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                if isCurrent {
                    Text("Current")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.accent)
                        .cornerRadius(4)
                }

                Spacer()

                // Show chevron if multiple refresh rates
                if group.hasMultipleRates {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(showRates ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: showRates)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                isFlashing ? Theme.accent.opacity(0.25) :
                isCurrent  ? Theme.accent.opacity(0.10) :
                isHovered  ? Color.primary.opacity(0.06) : Color.clear
            )
            .onHover { isHovered = $0 }
            .opacity(isSwitching && !isAnySwitching ? 0.45 : 1.0)
            .onTapGesture {
                guard !isSwitching else { return }
                if group.hasMultipleRates {
                    withAnimation(.easeInOut(duration: 0.2)) { showRates.toggle() }
                } else {
                    onSelectMode(group.bestMode)
                }
            }

            // Refresh rate picker (expanded)
            if showRates && group.hasMultipleRates {
                RefreshRatePicker(
                    modes: group.modes,
                    activeMode: activeMode,
                    switchingModeID: switchingModeID,
                    onSelect: onSelectMode
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Refresh Rate Picker

private struct RefreshRatePicker: View {
    let modes: [UnifiedMode]
    let activeMode: UnifiedMode?
    let switchingModeID: Int32?
    let onSelect: (UnifiedMode) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("Refresh Rate")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(spacing: 2) {
                ForEach(modes) { mode in
                    RatePill(
                        mode: mode,
                        isActive: mode.id == activeMode?.id,
                        isSwitching: switchingModeID == mode.id,
                        onTap: { onSelect(mode) }
                    )
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(6)
        }
    }
}

private struct RatePill: View {
    let mode: UnifiedMode
    let isActive: Bool
    let isSwitching: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                if isSwitching {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 10, height: 10)
                }
                Text(mode.refreshString)
                    .font(.caption2)
                    .fontWeight(isActive ? .medium : .regular)
                    .foregroundColor(isActive ? .white : .primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isActive ? Theme.accent :
                        isHovered ? Color.primary.opacity(0.06) : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - TagBadge

private struct TagBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .cornerRadius(3)
    }
}
