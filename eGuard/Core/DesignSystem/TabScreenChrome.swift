import SwiftUI

/// The header used by root tab screens, which hide the navigation bar and draw their own title row.
struct TabScreenHeader<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(EGuardTypography.headline)
                .foregroundStyle(EGuardColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack {
                leading()
                Spacer()
                trailing()
            }
        }
        .frame(minHeight: 44)
    }
}

/// Screen layout for a root tab: scrollable content with an optional header, no pinned actions.
struct TabScreen<Header: View, Content: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EGuardSpacing.lg) {
                header()
                content()
            }
            .padding(.horizontal, EGuardSpacing.md)
            .padding(.top, EGuardSpacing.xs)
            .padding(.bottom, EGuardSpacing.xl)
        }
        .background(EGuardColors.background)
    }
}
