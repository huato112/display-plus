import SwiftUI

/// Expandable HiDPI section: a one-tap on/off plus a BetterDisplay-style scaling picker that lists
/// the "looks like" Retina resolutions macOS hides from the public API (surfaced via `HiDPIService`).
struct HiDPIRowView: View {
    @ObservedObject var display: DisplayInfo
    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var options: [HiDPIService.ScaleOption] = []
    @State private var current: Scale? = nil

    private struct Scale: Equatable { let width: Int; let height: Int }

    private var isOn: Bool { current != nil }

    var body: some View {
        if display.isBuiltin {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isExpanded {
                    optionList
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity))
                }
            }
            .onAppear(perform: reload)
            .alert("HiDPI operation failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let msg = errorMessage { Text(msg) }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            MenuItemIcon(systemName: "sparkles", color: .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("HiDPI Mode").font(.body)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if isLoading {
                ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
            } else {
                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green).font(.caption)
                }
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(isHovered ? 0.06 : 0))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isExpanded.toggle() }
            if isExpanded { reload() }
        }
        .onHover { isHovered = $0 }
    }

    private var subtitle: String {
        if let c = current { return "Retina · looks like \(c.width) × \(c.height)" }
        return "Sharpen text on this display"
    }

    // MARK: - Scaling picker

    @ViewBuilder
    private var optionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HiDPIScaleRow(title: "Off (Native)", detail: nil, isCurrent: !isOn) { apply(nil) }

            if options.isEmpty {
                Text("No HiDPI scaling available for this display")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                ForEach(options) { opt in
                    HiDPIScaleRow(
                        title: opt.label,
                        detail: detail(for: opt),
                        isCurrent: current == Scale(width: opt.width, height: opt.height)
                    ) { apply(opt) }
                }
            }
        }
        .padding(.leading, 8)
        .padding(.bottom, 4)
    }

    private func detail(for opt: HiDPIService.ScaleOption) -> String? {
        let (nw, nh) = display.nativeResolution
        var parts: [String] = []
        if opt.refresh > 0 { parts.append("\(opt.refresh) Hz") }
        if opt.width == nw && opt.height == nh { parts.append("Default") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Actions

    /// Apply a scale, or pass nil to turn HiDPI off (back to native 1×).
    private func apply(_ opt: HiDPIService.ScaleOption?) {
        guard !isLoading else { return }
        isLoading = true
        let (nw, nh) = display.nativeResolution
        let displayID = display.displayID
        let uuid = display.displayUUID
        Task {
            let err: String?
            if let opt {
                err = await HiDPIService.shared.applyScale(
                    width: opt.width, height: opt.height, for: displayID, uuid: uuid)
            } else {
                err = await HiDPIService.shared.disableHiDPI(
                    for: displayID, uuid: uuid, nativeWidth: nw, nativeHeight: nh)
            }
            isLoading = false
            if let err {
                errorMessage = err
            } else {
                reload()
                HiDPIService.shared.refreshModes(for: display)
            }
        }
    }

    private func reload() {
        options = HiDPIService.shared.scaleOptions(for: display.displayID)
        if let c = HiDPIService.shared.currentScale(for: display.displayID) {
            current = Scale(width: c.width, height: c.height)
        } else {
            current = nil
        }
    }
}

// MARK: - Scale row

private struct HiDPIScaleRow: View {
    let title: String
    let detail: String?
    let isCurrent: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isCurrent ? "largecircle.fill.circle" : "circle")
                .font(.caption)
                .foregroundColor(isCurrent ? Theme.accent : .secondary)
            Text(title)
                .font(.caption)
                .foregroundColor(isCurrent ? .primary : .secondary)
                .monospacedDigit()
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if isCurrent {
                Text("Current")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.accent)
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(
            isCurrent ? Theme.accent.opacity(0.10) :
            isHovered ? Color.primary.opacity(0.06) : Color.clear
        )
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
    }
}
