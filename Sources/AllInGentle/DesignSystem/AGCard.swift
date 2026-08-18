import SwiftUI

/// A consistent padded container for grouping related content.
///
/// `AGCard` applies the surface background, border, and corner radius tokens,
/// and lightens the border on hover to communicate interactivity without
/// changing the background.
public struct AGCard<Content: View>: View {
    @State private var isHovered = false

    public let content: Content
    public let padding: CGFloat

    public init(padding: CGFloat = AGSpacing.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(AGColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: AGSpacing.cornerRadiusLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AGSpacing.cornerRadiusLarge, style: .continuous)
                    .stroke(isHovered ? AGColors.borderHover : AGColors.border, lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
