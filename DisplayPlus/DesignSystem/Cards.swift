import SwiftUI

/// Uppercase group label shown above a `Card`. Pure presentation; no state.
struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(Theme.secondaryText)
            .padding(.horizontal, Theme.rowHPadding)
            .padding(.top, Theme.sectionHeaderTopPadding)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Rounded, inset, subtly-filled container that groups a section's rows.
/// Replaces the old hairline `Divider().opacity(0.3)` separators.
struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.vertical, Theme.cardContentVPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.cardFill)
        )
        .padding(.horizontal, Theme.cardInset)
    }
}
