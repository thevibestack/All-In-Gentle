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
}
