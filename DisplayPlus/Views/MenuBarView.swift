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
    @State private var expandedDisplayIDs: Set<CGDirectDisplayID> = []
    @State private var hasInitialExpanded = false
    @State private var quitHovered = false

    private var hasUnlistedDisconnects: Bool {
        DisplayConnectionService.shared.hasUnlistedDisconnects(amongListed: displayManager.displays)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                    SectionHeader("Displays")
                    Card {
                        ForEach(displayManager.displays) { display in
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
                        if hasUnlistedDisconnects {
                            ConnectAllDisplaysRow()
                        }
                    }
                }
            }

            Divider().opacity(Theme.dividerOpacity)
            HStack {
                Text("Display+")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "xmark")
                        .padding(.horizontal, Theme.lg)
                        .padding(.vertical, Theme.sm)
                        .background(Theme.hover(quitHovered))
                        .cornerRadius(Theme.md)
                }
                .buttonStyle(.plain)
                .foregroundColor(quitHovered ? .red : .secondary)
                .onHover { quitHovered = $0 }
                .help("Quit Display+")
            }
            .padding(.horizontal, Theme.rowHPadding)
            .padding(.vertical, Theme.md)
        }
        .frame(width: Theme.popoverWidth, alignment: .top)
        .tint(Theme.accent)
        .frame(minHeight: Theme.popoverMinHeight, maxHeight: Theme.popoverMaxHeight)
        .padding(.vertical, Theme.lg)
        .onReceive(displayManager.$displays) { newDisplays in
            let enabledIDs = Set(newDisplays.filter { $0.isEnabled }.map { $0.displayID })
            expandedDisplayIDs = expandedDisplayIDs.intersection(enabledIDs)
            if !hasInitialExpanded && !enabledIDs.isEmpty {
                expandedDisplayIDs = enabledIDs
                hasInitialExpanded = true
            }
        }
    }
}

// MARK: - DisplayRowView

struct DisplayRowView: View {
    @ObservedObject var display: DisplayInfo
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
