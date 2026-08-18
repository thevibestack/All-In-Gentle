import SwiftUI

/// Reusable dashboard card container (spec DS-4): the AG design-system
/// surface/border/corner/hover treatment, sized to fill its grid cell.
public struct DashboardCard<Content: View>: View {
    public let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        AGCard(padding: AGSpacing.cardPaddingDense) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
