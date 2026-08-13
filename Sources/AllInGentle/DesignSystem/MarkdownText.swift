import SwiftUI
import MarkdownUI

/// Renders Markdown content using the design system palette.
///
/// ``MarkdownText`` wraps MarkdownUI so chat assistant messages and other
/// text surfaces can display rich content (emphasis, code, lists, links) without
/// extra work at the call site. Code block copy actions are intentionally left
/// for v2.
public struct MarkdownText: View {
    private let content: String

    public init(_ content: String) {
        self.content = content
    }

    public var body: some View {
        Markdown(content)
            .markdownTheme(
                Theme()
                    .text {
                        ForegroundColor(AGColors.textPrimary)
                    }
                    .strong {
                        FontWeight(.semibold)
                    }
                    .link {
                        ForegroundColor(AGColors.accent)
                    }
                    .code {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                        BackgroundColor(AGColors.surfaceSecondary)
                    }
                    .paragraph { configuration in
                        configuration.label
                            .fixedSize(horizontal: false, vertical: true)
                            .relativeLineSpacing(.em(0.25))
                    }
                    .blockquote { configuration in
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AGColors.border)
                                .relativeFrame(width: .em(0.2))
                            configuration.label
                                .markdownTextStyle { ForegroundColor(AGColors.textSecondary) }
                                .relativePadding(.horizontal, length: .em(1))
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .codeBlock { configuration in
                        ScrollView(.horizontal) {
                            configuration.label
                                .fixedSize(horizontal: false, vertical: true)
                                .markdownTextStyle {
                                    FontFamilyVariant(.monospaced)
                                    FontSize(.em(0.85))
                                }
                                .padding(AGSpacing.small)
                        }
                        .background(AGColors.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: AGSpacing.cornerRadius, style: .continuous))
                    }
                    .thematicBreak {
                        Divider()
                            .overlay(AGColors.border)
                    }
            )
            .textSelection(.enabled)
    }
}
