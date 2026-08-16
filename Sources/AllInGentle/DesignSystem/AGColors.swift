import SwiftUI

/// Semantic color tokens for the All-In-Gentle design system.
///
/// All colors adapt automatically to the current appearance (light/dark) using
/// `NSColor` dynamic providers. Views must consume these tokens instead of raw
/// `Color` literals so the palette stays consistent across every feature.
public enum AGColors {
    // MARK: - Surfaces

    public static var background: Color {
        Color(
            nsColor: NSColor(
                name: "AGBackground",
                dynamicProvider: { appearance in
                    appearance.isDark
                        ? NSColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1.0)
                        : NSColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1.0)
                }))
    }

    public static var surface: Color {
        Color(
            nsColor: NSColor(
                name: "AGSurface",
                dynamicProvider: { appearance in
                    appearance.isDark
                        ? NSColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0)
                        : NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.0)
                }))
    }

    public static var surfaceSecondary: Color {
        Color(
            nsColor: NSColor(
                name: "AGSurfaceSecondary",
                dynamicProvider: { appearance in
                    appearance.isDark
                        ? NSColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1.0)
                        : NSColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0)
                }))
    }

    // MARK: - Borders

    public static var border: Color {
        Color(
            nsColor: NSColor(
                name: "AGBorder",
                dynamicProvider: { appearance in
                    appearance.isDark
                        ? NSColor(red: 0.24, green: 0.26, blue: 0.30, alpha: 1.0)
                        : NSColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 1.0)
                }))
    }

    public static var borderHover: Color {
        Color(
            nsColor: NSColor(
                name: "AGBorderHover",
                dynamicProvider: { appearance in
                    appearance.isDark
                        ? NSColor(red: 0.35, green: 0.38, blue: 0.44, alpha: 1.0)
                        : NSColor(red: 0.78, green: 0.80, blue: 0.84, alpha: 1.0)
                }))
    }

    // MARK: - Text

    public static var textPrimary: Color {
        Color(
            nsColor: NSColor(
                name: "AGTextPrimary",
                dynamicProvider: { appearance in
                    appearance.isDark
                        ? NSColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0)
                        : NSColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0)
                }))
    }

    public static var textSecondary: Color {
        Color(
            nsColor: NSColor(
                name: "AGTextSecondary",
                dynamicProvider: { appearance in
                    appearance.isDark
                        ? NSColor(red: 0.62, green: 0.65, blue: 0.70, alpha: 1.0)
                        : NSColor(red: 0.44, green: 0.47, blue: 0.52, alpha: 1.0)
                }))
    }

    // MARK: - Accent

    /// Single desaturated accent color (electric blue). Used sparingly for the
    /// most important interactive elements only.
    public static var accent: Color {
        Color(
            nsColor: NSColor(
                name: "AGAccent",
                dynamicProvider: { appearance in
                    appearance.isDark
                        ? NSColor(red: 0.35, green: 0.60, blue: 0.95, alpha: 1.0)
                        : NSColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1.0)
                }))
    }

    /// Text on accent-colored surfaces. White in light appearance; near-black
    /// in dark appearance so it keeps WCAG AA (>=4.5:1) against both `accent`
    /// and `statusError` (white-on-dark-accent measured ~2.9:1).
    public static var accentText: Color {
        Color(
            nsColor: NSColor(
                name: "AGAccentText",
                dynamicProvider: { appearance in
                    appearance.isDark
                        ? NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0)
                        : NSColor.white
                }))
    }

    // MARK: - Status

    public static var statusLive: Color {
        Color(
            nsColor: NSColor(
                name: "AGStatusLive",
                dynamicProvider: { appearance in
                    appearance.isDark
                        ? NSColor(red: 0.25, green: 0.85, blue: 0.45, alpha: 1.0)
                        : NSColor(red: 0.15, green: 0.65, blue: 0.30, alpha: 1.0)
                }))
    }

    public static var statusPlaceholder: Color {
        Color(
            nsColor: NSColor(
                name: "AGStatusPlaceholder",
                dynamicProvider: { appearance in
                    appearance.isDark
                        ? NSColor(red: 0.95, green: 0.70, blue: 0.20, alpha: 1.0)
                        : NSColor(red: 0.80, green: 0.50, blue: 0.10, alpha: 1.0)
                }))
    }

    public static var statusDisabled: Color {
        Color(
            nsColor: NSColor(
                name: "AGStatusDisabled",
                dynamicProvider: { appearance in
                    appearance.isDark
                        ? NSColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 1.0)
                        : NSColor(red: 0.50, green: 0.53, blue: 0.57, alpha: 1.0)
                }))
    }

    public static var statusError: Color {
        Color(
            nsColor: NSColor(
                name: "AGStatusError",
                dynamicProvider: { appearance in
                    appearance.isDark
                        ? NSColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1.0)
                        : NSColor(red: 0.80, green: 0.15, blue: 0.15, alpha: 1.0)
                }))
    }
}

extension NSAppearance {
    fileprivate var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
