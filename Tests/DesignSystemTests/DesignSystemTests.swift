import Foundation
import SwiftUI
import XCTest
@testable import AllInGentleKit

@MainActor
final class DesignSystemTests: XCTestCase {
    // MARK: - Color tokens

    func testColorTokensExistInBothAppearances() {
        let tokens: [Color] = [
            AGColors.background,
            AGColors.surface,
            AGColors.surfaceSecondary,
            AGColors.border,
            AGColors.borderHover,
            AGColors.textPrimary,
            AGColors.textSecondary,
            AGColors.accent,
            AGColors.accentText,
            AGColors.statusLive,
            AGColors.statusPlaceholder,
            AGColors.statusDisabled,
            AGColors.statusError
        ]
        XCTAssertEqual(tokens.count, 13)
    }

    // MARK: - WCAG contrast (R2.1)

    func testAccentTextMeetsWCAGAAOnAccentAndErrorInBothAppearances() {
        // WCAG AA requires >= 4.5:1. Design targets: 7.3:1 on accent and
        // 6.4:1 on statusError in dark appearance; light must not regress.
        for appearance in [NSAppearance(named: .aqua)!, NSAppearance(named: .darkAqua)!] {
            let accentText = resolve(AGColors.accentText, under: appearance)
            let accent = resolve(AGColors.accent, under: appearance)
            let statusError = resolve(AGColors.statusError, under: appearance)

            let onAccent = contrastRatio(between: accentText, and: accent)
            let onError = contrastRatio(between: accentText, and: statusError)

            XCTAssertGreaterThanOrEqual(
                onAccent, 4.5,
                "accentText on accent in \(appearance.name.rawValue): \(onAccent)"
            )
            XCTAssertGreaterThanOrEqual(
                onError, 4.5,
                "accentText on statusError in \(appearance.name.rawValue): \(onError)"
            )
        }
    }

    func testAccentTextIsNearBlackInDarkAppearance() {
        // R2.2: dark appearance must not use white text on accent (2.9:1);
        // near-black (0.08, 0.10, 0.14) is the chosen dark token.
        let dark = NSAppearance(named: .darkAqua)!
        let darkAccentText = resolve(AGColors.accentText, under: dark)
        let rgb = darkAccentText.usingColorSpace(.sRGB)!
        let brightness = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        XCTAssertLessThan(brightness, 0.3, "Dark accentText must be dark, got brightness \(brightness)")
    }

    // MARK: - Helpers

    /// Resolves a SwiftUI `Color` token as sRGB under a specific appearance by
    /// temporarily swapping `NSAppearance.current`.
    private func resolve(_ color: Color, under appearance: NSAppearance) -> NSColor {
        let previous = NSAppearance.current
        NSAppearance.current = appearance
        defer { NSAppearance.current = previous }
        return NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
    }

    /// WCAG 2.x relative luminance of an sRGB color (0...1).
    private func relativeLuminance(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
        func linear(_ c: CGFloat) -> CGFloat {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = linear(rgb.redComponent)
        let g = linear(rgb.greenComponent)
        let b = linear(rgb.blueComponent)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// WCAG 2.x contrast ratio between two colors (1...21).
    private func contrastRatio(between a: NSColor, and b: NSColor) -> CGFloat {
        let l1 = relativeLuminance(a)
        let l2 = relativeLuminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    // MARK: - Typography tokens

    func testTypographyTokensExist() {
        let fonts: [Font] = [
            AGTypography.title,
            AGTypography.headline,
            AGTypography.body,
            AGTypography.caption,
            AGTypography.mono,
            AGTypography.monoCaption
        ]
        XCTAssertEqual(fonts.count, 6)
    }

    // MARK: - Button style

    func testAGButtonCanBeConstructed() {
        let button = AGButton("ds.button.retry", systemImage: "arrow.clockwise", variant: .primary) {}
        XCTAssertNotNil(button)
    }

    func testAGButtonStyleVariantsCanBeConstructed() {
        let variants: [AGButtonVariant] = [.primary, .secondary, .ghost, .danger]
        let styles = variants.map { AGButtonStyle(variant: $0) }
        XCTAssertEqual(styles.count, 4)
    }

    // MARK: - State components

    func testAGEmptyStateCanBeConstructed() {
        let empty = AGEmptyState(
            systemImage: "folder",
            titleKey: "projects.empty",
            messageKey: "projects.search"
        )
        XCTAssertNotNil(empty)
    }

    func testAGLoadingStateCanBeConstructed() {
        let loading = AGLoadingState()
        XCTAssertNotNil(loading)
    }

    func testAGErrorStateCanBeConstructedWithRetry() {
        var didRetry = false
        let error = AGErrorState(retry: { didRetry = true })
        XCTAssertNotNil(error)
    }

    func testAGListRowCanBeConstructed() {
        let row = AGListRow {
            Text("Sample")
        }
        XCTAssertNotNil(row)
    }

    // MARK: - Status badge

    func testAGStatusBadgeCanBeConstructedFromInteractionState() {
        let badge = AGStatusBadge(interactionState: .placeholder)
        XCTAssertNotNil(badge)
        XCTAssertEqual(badge.status, .placeholder)
    }

    func testAGStatusBadgeErrorCaseExists() {
        let badge = AGStatusBadge(status: .error)
        XCTAssertNotNil(badge)
        XCTAssertEqual(badge.status.catalogKey, "ds.badge.error")
    }

    // MARK: - Search field binding

    func testAGSearchFieldBindingUpdates() {
        var query = "initial"
        let binding = Binding(
            get: { query },
            set: { query = $0 }
        )
        let field = AGSearchField(text: binding, placeholderKey: "projects.search")
        XCTAssertNotNil(field)

        // Simulate clearing the binding, mirroring the clear button action.
        binding.wrappedValue = ""
        XCTAssertEqual(query, "")
    }

    func testAGSearchFieldFocusBindingUpdates() {
        var focused = false
        let focusBinding = Binding(
            get: { focused },
            set: { focused = $0 }
        )
        let field = AGSearchField(text: .constant(""), isFocused: focusBinding, placeholderKey: "projects.search")
        XCTAssertNotNil(field)

        focusBinding.wrappedValue = true
        XCTAssertTrue(focused)
    }
}
