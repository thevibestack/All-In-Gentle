import SwiftUI

/// A unified search field with clear button, focus state, and keyboard shortcut hint.
public struct AGSearchField: View {
    @Binding public var text: String
    @Binding public var isFocused: Bool
    @FocusState private var fieldFocused: Bool

    public let placeholderKey: String
    public let commandHintKey: String?

    public init(
        text: Binding<String>,
        isFocused: Binding<Bool> = .constant(false),
        placeholderKey: String,
        commandHintKey: String? = "ds.search.commandHint"
    ) {
        self._text = text
        self._isFocused = isFocused
        self.placeholderKey = placeholderKey
        self.commandHintKey = commandHintKey
    }

    public var body: some View {
        HStack(spacing: AGSpacing.xSmall) {
            Image(systemName: "magnifyingglass")
                .font(AGTypography.caption)
                .foregroundStyle(AGColors.textSecondary)

            ZStack(alignment: .leading) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(AGTypography.body)
                    .foregroundStyle(AGColors.textPrimary)
                    .focused($fieldFocused)
                    .accessibilityLabel(L(placeholderKey))

                if text.isEmpty && !fieldFocused {
                    Text(L(placeholderKey))
                        .font(AGTypography.body)
                        .foregroundStyle(AGColors.textSecondary)
                        .allowsHitTesting(false)
                }
            }

            if !text.isEmpty {
                Button {
                    text = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AGTypography.caption)
                        .foregroundStyle(AGColors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("ds.button.clear"))
            } else if let commandHintKey, !fieldFocused {
                Text(L(commandHintKey))
                    .font(AGTypography.caption)
                    .foregroundStyle(AGColors.textSecondary)
                    .padding(.horizontal, AGSpacing.xSmall)
                    .padding(.vertical, 2)
                    .background(AGColors.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: AGSpacing.cornerRadiusSmall, style: .continuous))
            }
        }
        .padding(.horizontal, AGSpacing.small)
        .padding(.vertical, AGSpacing.xSmall)
        .background(AGColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AGSpacing.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AGSpacing.cornerRadius, style: .continuous)
                .stroke(fieldFocused ? AGColors.borderHover : AGColors.border, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: fieldFocused)
        .onChange(of: isFocused) { _, focused in
            fieldFocused = focused
        }
        .onChange(of: fieldFocused) { _, focused in
            isFocused = focused
        }
    }
}
