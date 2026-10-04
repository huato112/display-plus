import SwiftUI

// MARK: - Shared Icon Helper

/// A colored rounded-square SF Symbol icon, consistent with macOS Settings style.
struct MenuItemIcon: View {
    let systemName: String
    var color: Color = Theme.accent

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: Theme.iconGlyph, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: Theme.iconSize, height: Theme.iconSize)
            .background(RoundedRectangle(cornerRadius: Theme.iconCorner).fill(color))
    }
}

// MARK: - ExpandableRow

struct ExpandableRow: View {
    let icon: String
    var iconColor: Color = Theme.accent
    let label: String
    var subtitle: String? = nil
    @Binding var isExpanded: Bool
    @State private var isHovered = false

    var body: some View {
        HStack {
            MenuItemIcon(systemName: icon, color: iconColor)
            Text(label).font(.body)
            Spacer()
            if let sub = subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.2), value: isExpanded)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.rowHPadding)
        .padding(.vertical, Theme.rowVPadding)
        .background(Theme.hover(isHovered))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .onHover { isHovered = $0 }
        .accessibilityLabel(isExpanded ? "\(label), Expanded" : "\(label), Collapsed")
        .accessibilityHint("Click to expand or collapse this section")
        .accessibilityAddTraits(.isButton)
        .help("Click to expand or collapse this section")
    }
}

struct MenuBarView: View {
    @EnvironmentObject var displayManager: DisplayManager
    @ObservedObject private var updateService = UpdateService.shared
    @ObservedObject private var settings = SettingsService.shared
    @ObservedObject private var virtualDisplayService = VirtualDisplayService.shared
    @State private var expandedDisplayIDs: Set<CGDirectDisplayID> = []
    @State private var showArrangement: Bool = false
    @State private var showVirtualDisplays: Bool = false
    @State private var showAutoBrightness: Bool = false
    @State private var showSettings: Bool = false
    @State private var quitHovered = false
    @State private var hasInitialExpanded = false

    private var visibleDisplays: [DisplayInfo] {
        displayManager.displays.filter { !virtualDisplayService.isVirtualDisplay($0.displayID) }
    }

    /// Displays marked disconnected in a *previous* session (persisted) that aren't currently in the
    /// list — they dropped off the OS online list and we have no live ID to reconnect them inline.
    /// Recovered as a group via "Connect all displays".
    private var hasGhostDisconnects: Bool {
        DisplayConnectionService.shared.hasUnlistedDisconnects(amongListed: displayManager.displays)
    }

    var body: some View {
        VStack(spacing: 0) {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                // DISPLAYS — unified list; a display turned off shows dimmed with its switch off.
                SectionHeader("Displays")
                Card {
                    ForEach(visibleDisplays) { display in
                        VStack(spacing: 0) {
                            DisplayRowView(
                                display: display,
                                isExpanded: expandedDisplayIDs.contains(display.displayID),
                                onToggleExpand: {
                                    guard display.isEnabled else { return }
                                    if expandedDisplayIDs.contains(display.displayID) {
                                        expandedDisplayIDs.remove(display.displayID)
                                    } else {
                                        expandedDisplayIDs.insert(display.displayID)
                                    }
                                }
                            )
                            if display.isEnabled && expandedDisplayIDs.contains(display.displayID) {
                                DisplayDetailView(display: display)
                            }
                        }
                    }
                    if hasGhostDisconnects {
                        ConnectAllDisplaysRow()
                    }
                }

                // PRESETS
                SectionHeader("Presets")
                Card { PresetListView() }

                // ARRANGE — only meaningful with more than one display.
                if visibleDisplays.count > 1 {
                    SectionHeader("Arrange")
                    Card {
                        ExpandableRow(
                            icon: "rectangle.3.offgrid",
                            iconColor: Theme.accent,
                            label: "Arrange Displays",
                            isExpanded: $showArrangement
                        )
                        if showArrangement {
                            ArrangementView()
                                .environmentObject(displayManager)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }

                // BRIGHTNESS — unified slider, when enabled in Settings.
                if settings.showCombinedBrightness {
                    SectionHeader("Brightness")
                    Card { CombinedBrightnessView(displays: displayManager.displays) }
                }

                // TOOLS
                SectionHeader("Tools")
                Card {
                    ExpandableRow(
                        icon: "display.2",
                        iconColor: Theme.accent,
                        label: "Virtual Displays",
                        isExpanded: $showVirtualDisplays
                    )
                    if showVirtualDisplays {
                        VirtualDisplayView()
                            .padding(.leading, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    ExpandableRow(
                        icon: "sun.and.horizon.fill",
                        iconColor: .orange,
                        label: "Auto Brightness",
                        isExpanded: $showAutoBrightness
                    )
                    if showAutoBrightness {
                        AutoBrightnessView()
                            .padding(.leading, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                // SETTINGS (+ update banner)
                SectionHeader("Settings")
                Card {
                    ExpandableRow(
                        icon: "gearshape.fill",
                        iconColor: .gray,
                        label: "Settings",
                        isExpanded: $showSettings
                    )
                    if showSettings {
                        SettingsView()
                            .padding(.leading, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if updateService.hasUpdate, let ver = updateService.latestVersion {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.green)
                                .frame(width: 20)
                                .accessibilityHidden(true)
                            Text("New update v\(ver) available")
                                .font(.caption)
                                .foregroundColor(.green)
                            Spacer()
                            Button("View") { updateService.openReleasePage() }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundColor(.green)
                                .help("Download and install the latest version")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.08))
                        .cornerRadius(6)
                        .padding(.horizontal, 8)
                    }
                }
            }
        }

        Divider().opacity(0.3)

        // Version + Quit row (fixed at bottom, outside scroll)
        HStack {
            Text("Display+ v\(updateService.currentVersion)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            Spacer()
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "xmark")
                        .accessibilityHidden(true)
                    Text("Quit")
                }
                .font(.body)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(quitHovered ? Color.primary.opacity(0.06) : .clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(quitHovered ? .red : .secondary)
            .onHover { quitHovered = $0 }
            .help("Quit Display+")
        }
        // Footer bar keeps its own padding — it's a fixed bottom bar, not a Theme list row.
        .padding(.horizontal, 12)
        .padding(.vertical, 6)

        } // end VStack
        .frame(width: Theme.popoverWidth, alignment: .top)
        .tint(Theme.accent)
        .frame(minHeight: Theme.popoverMinHeight, maxHeight: Theme.popoverMaxHeight)
        .padding(.vertical, 8)
        .onReceive(displayManager.$displays) { newDisplays in
            // Only enabled displays can stay expanded; a display turned off collapses automatically.
            let enabledIDs = Set(newDisplays.filter { $0.isEnabled }.map { $0.displayID })
            expandedDisplayIDs = expandedDisplayIDs.intersection(enabledIDs)

            if !hasInitialExpanded && !enabledIDs.isEmpty {
                expandedDisplayIDs = enabledIDs
                hasInitialExpanded = true
            }
        }
        .task {
            if settings.checkUpdatesOnLaunch {
                await updateService.checkForUpdates()
            }
        }
    }
}

// MARK: - SettingsView (Phase 12: embedded in MenuBarView)

struct SettingsView: View {
    @ObservedObject private var settings = SettingsService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Launch at Login toggle
            Toggle(isOn: Binding(
                get: { settings.launchAtLogin },
                set: { newValue in
                    if newValue {
                        LaunchService.shared.enable()
                    } else {
                        LaunchService.shared.disable()
                    }
                    settings.launchAtLogin = newValue
                }
            )) {
                HStack(spacing: 6) {
                    MenuItemIcon(systemName: "power", color: .green)
                        .accessibilityHidden(true)
                    Text("Launch at Login")
                        .font(.body)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .help("Automatically launch Display+ at login")

            // First-launch prompt: recommend enabling launch at login
            if !settings.launchAtLoginPrompted {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text("Recommended to launch at login")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Got it") {
                        settings.launchAtLoginPrompted = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .onAppear {
                    // Mark as prompted so it only shows once
                    // User dismisses manually via "Got it" button
                }
            }

            // Show Combined Brightness toggle
            Toggle(isOn: $settings.showCombinedBrightness) {
                HStack(spacing: 6) {
                    MenuItemIcon(systemName: "sun.min.fill", color: .yellow)
                        .accessibilityHidden(true)
                    Text("Show Combined Brightness Control")
                        .font(.body)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .help("Show unified brightness slider for all displays in menu bar")

            // Check for updates on launch toggle
            Toggle(isOn: $settings.checkUpdatesOnLaunch) {
                HStack(spacing: 6) {
                    MenuItemIcon(systemName: "arrow.clockwise.circle", color: Theme.accent)
                        .accessibilityHidden(true)
                    Text("Check for updates on launch")
                        .font(.body)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .help("Automatically check for new versions on every launch")
        }
        .padding(.vertical, 6)
    }
}

// MARK: - DisplayRowView

struct DisplayRowView: View {
    @ObservedObject var display: DisplayInfo
    @EnvironmentObject var displayManager: DisplayManager
    @State private var isHovered: Bool = false

    let isExpanded: Bool
    let onToggleExpand: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                // Expand affordance — only meaningful while the display is on. When off, keep the
                // 16pt slot so the icon/name stay aligned, but show no chevron.
                Group {
                    if display.isEnabled {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .rotationEffect(Angle(degrees: isExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.2), value: isExpanded)
                    }
                }
                .frame(width: 16)
                .accessibilityHidden(true)

                MenuItemIcon(systemName: display.isBuiltin ? "laptopcomputer" : "display",
                             color: display.isEnabled ? Theme.accent : .gray)
                VStack(alignment: .leading, spacing: 1) {
                    Text(display.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !display.isEnabled {
                        Text("Off")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if let mode = display.currentDisplayMode {
                        Text(mode.resolutionString)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                if display.isMain {
                    Text("Main")
                        .font(.caption2)
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.accent.opacity(0.12))
                        .cornerRadius(3)
                }
                Spacer()
            }
            .opacity(display.isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }
            .help(display.isEnabled ? "Expand display control panel"
                                    : "Display is off — turn it on with the switch")

            // On/off switch — trailing in the name row. Disconnects/reconnects from the desktop.
            DisplayPowerToggle(display: display)
                .padding(.leading, 6)
        }
        .padding(.horizontal, Theme.rowHPadding)
        .padding(.vertical, Theme.rowVPadding)
        .background(Theme.hover(isHovered))
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open System Settings", systemImage: "display")
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(display.name, forType: .string)
            } label: {
                Label("Copy Display Name", systemImage: "doc.on.doc")
            }
        }
        .accessibilityLabel("Display: \(display.name)\(display.isMain ? ", Main Display" : "")\(isExpanded ? ", Expanded" : ", Collapsed")")
        .accessibilityHint("Click to expand control panel")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - ConnectAllDisplaysRow

/// Recovery action (BetterDisplay-style "connect to all displays"). A display turned off in a
/// previous session vanished from the OS online list, so it can't be shown inline. This re-enables
/// every disabled display the system still knows about and clears the persisted off-state.
struct ConnectAllDisplaysRow: View {
    @EnvironmentObject var displayManager: DisplayManager
    @State private var isHovered = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                errorMessage = displayManager.connectAllDisplays()
                if errorMessage != nil {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        errorMessage = nil
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    MenuItemIcon(systemName: "rectangle.badge.plus", color: .green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Connect all displays")
                        Text("Turn a display back on")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Re-enable every display that was turned off — including ones disconnected before a restart")

            if let msg = errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(isHovered ? 0.06 : 0))
        .onHover { isHovered = $0 }
    }
}

// MARK: - DisplayPowerToggle

/// Compact on/off switch shown trailing in each display's header row — disconnects/reconnects the
/// display from the desktop, with the same behavior for built-in and external displays. Hidden when
/// the private enable/disable API is unavailable. On failure (e.g. the last-active guard) the switch
/// snaps back to the real state.
struct DisplayPowerToggle: View {
    @ObservedObject var display: DisplayInfo
    @EnvironmentObject var displayManager: DisplayManager
    @State private var errorMessage: String?

    var body: some View {
        if DisplayConnectionService.shared.isAvailable {
            HStack(spacing: 4) {
                if let errorMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .help(errorMessage)
                        .accessibilityLabel(errorMessage)
                }
                Toggle("", isOn: Binding(
                    get: { display.isEnabled },
                    set: { apply(connected: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(display.isEnabled ? "Turn this display off (disconnect from the desktop)"
                                        : "Turn this display on")
            }
        }
    }

    private func apply(connected: Bool) {
        if let err = displayManager.setConnected(connected, for: display) {
            // Failed (e.g. last-active-display guard) → display.isEnabled didn't change;
            // refresh so the switch snaps back to the real state instead of sticking, and show why.
            displayManager.refreshDisplays()
            errorMessage = err
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                errorMessage = nil
            }
        }
    }
}
