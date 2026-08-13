import SwiftUI

/// A consistent styled row for list-based feature views.
///
/// `AGListRow` wraps row content in an `AGCard` and applies standard vertical
/// spacing so every list row shares the same surface, border, and hover
/// treatment. Use it inside `List` or `Form` rows across feature views.
public struct AGListRow<Content: View>: View {
    public let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        AGCard {
            content
        }
        .padding(.vertical, AGSpacing.xxSmall)
    }
}
