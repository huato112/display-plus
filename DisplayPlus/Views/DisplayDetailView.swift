import SwiftUI

// MARK: - DisplayDetailView

struct DisplayDetailView: View {
    @ObservedObject var display: DisplayInfo
    @State private var showModeList: Bool = false

    private func sectionKey(_ name: String) -> String {
        "fd.expanded.\(display.displayUUID).\(name)"
    }

    private func loadExpanded(_ name: String, default value: Bool) -> Bool {
        let key = sectionKey(name)
        guard UserDefaults.standard.object(forKey: key) != nil else { return value }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func saveExpanded(_ name: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: sectionKey(name))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // HiDPI toggle — before mode list (natural workflow: enable HiDPI → pick resolution)
            HiDPIRowView(display: display)

            // Display mode list toggle row
            ExpandableRow(
                icon: "rectangle.on.rectangle",
                label: "Display Mode",
                subtitle: {
                    var parts: [String] = []
                    if let mode = display.currentDisplayMode {
                        parts.append(mode.resolutionString)
                    }
                    if display.currentDisplayMode?.isHiDPI == true {
                        parts.append("HiDPI")
                    }
                    return parts.joined(separator: " · ")
                }(),
                isExpanded: $showModeList
            )

            if showModeList {
                DisplayModeListView(display: display)
                    .padding(.leading, 8)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }

        }
        .padding(.leading, 32)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .onAppear {
            showModeList = loadExpanded("modeList", default: false)
        }
        .onChange(of: showModeList) { _, v in saveExpanded("modeList", v) }
    }
}
