import SwiftUI

/// Deterministic typographic styles for the All-In-Gentle design system.
///
/// The system uses SF Pro for interface text and SF Mono for code or metrics.
/// No custom fonts are bundled; sizes and weights are fixed to keep the visual
/// rhythm predictable across macOS Dynamic Type settings.
public enum AGTypography {
    /// Primary display style for view titles and major headings.
    public static var title: Font {
        Font.system(.title2, design: .default, weight: .semibold)
    }

    /// Section headings and card titles.
    public static var headline: Font {
        Font.system(.headline, design: .default, weight: .semibold)
    }

    /// Body text for paragraphs and list content.
    public static var body: Font {
        Font.system(.body, design: .default, weight: .regular)
    }

    /// Small supporting text, metadata, and captions.
    public static var caption: Font {
        Font.system(.caption, design: .default, weight: .regular)
    }

    /// Monospaced style for code, identifiers, metrics, and numeric data.
    public static var mono: Font {
        Font.system(.body, design: .monospaced, weight: .regular)
    }

    /// Monospaced caption for compact numeric data such as token counts.
    public static var monoCaption: Font {
        Font.system(.caption, design: .monospaced, weight: .regular)
    }

    // MARK: - Metric numerals (D2)

    /// Metric headline numeral size in points: 28pt semibold SF Mono.
    ///
    /// Exposed as a raw `CGFloat` so tests can pin the 28–34pt spec range
    /// (`Font` itself is opaque and cannot be read back).
    public static let metricSize: CGFloat = 28

    /// Metric caption size in points: 11pt SF Mono (11–12pt spec range).
    public static let metricCaptionSize: CGFloat = 11

    /// Large metric numeral — the visual anchor of a dashboard card.
    public static var metric: Font {
        Font.system(size: metricSize, weight: .semibold, design: .monospaced)
    }

    /// Small metric caption for deltas, rates, and secondary values.
    public static var metricCaption: Font {
        Font.system(size: metricCaptionSize, weight: .regular, design: .monospaced)
    }
}
