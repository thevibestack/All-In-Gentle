import CoreGraphics

/// Layout constants for the All-In-Gentle design system.
///
/// All spacing and sizing values are multiples of 4 to keep the rhythm
/// consistent across light and dark modes.
public enum AGSpacing {
    // MARK: - Padding

    public static let xxSmall: CGFloat = 4
    public static let xSmall: CGFloat = 8
    public static let small: CGFloat = 12
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let xLarge: CGFloat = 32
    public static let xxLarge: CGFloat = 48

    // MARK: - Corners

    public static let cornerRadiusSmall: CGFloat = 6
    public static let cornerRadius: CGFloat = 8
    public static let cornerRadiusLarge: CGFloat = 12

    // MARK: - Icon sizes

    public static let iconSmall: CGFloat = 12
    public static let iconMedium: CGFloat = 16
    public static let iconLarge: CGFloat = 20

    // MARK: - Row heights

    public static let rowHeightCompact: CGFloat = 28
    public static let rowHeight: CGFloat = 36
    public static let rowHeightLarge: CGFloat = 44

    // MARK: - Component insets

    public static let cardPadding: CGFloat = medium
    public static let buttonPaddingHorizontal: CGFloat = medium
    public static let buttonPaddingVertical: CGFloat = xSmall
    public static let badgePaddingHorizontal: CGFloat = 6
    public static let badgePaddingVertical: CGFloat = 2

    // MARK: - Dense scale (Stats-style dashboard)

    /// Tighter card padding for the dashboard grid (spec: 12–14).
    public static let cardPaddingDense: CGFloat = 12
    /// Tighter dashboard grid gap (spec: == 12).
    public static let gridGapDense: CGFloat = 12
    /// Tighter sidebar row padding for the dense shell (spec: 4–6).
    public static let sidebarRowPaddingDense: CGFloat = 4
}
