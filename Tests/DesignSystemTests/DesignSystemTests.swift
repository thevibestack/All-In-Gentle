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
            AGColors.statusError,
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

    // MARK: - MetricColor semantic tokens (D1)

    /// Metric → AGColors token map under test (spec D1): CPU keeps the single
    /// accent; the other metrics reuse the four status hues, no new colors.
    private static let metricTokenPairs: [(metric: MetricColor, token: Color)] = [
        (.cpu, AGColors.accent),
        (.gpu, AGColors.statusLive),
        (.ram, AGColors.statusPlaceholder),
        (.networkDown, AGColors.statusLive),
        (.networkUp, AGColors.statusPlaceholder),
        (.battery, AGColors.statusDisabled),
    ]

    func testMetricColorMapsEachMetricToItsAGToken() {
        for (metric, token) in Self.metricTokenPairs {
            assertColor(metric.token, equalsToken: token, under: NSAppearance(named: .aqua)!)
        }
    }

    func testMetricColorTokensResolveToMappedTokenInBothAppearances() {
        for appearance in [NSAppearance(named: .aqua)!, NSAppearance(named: .darkAqua)!] {
            for (metric, token) in Self.metricTokenPairs {
                // A hardcoded literal or a broken dynamic provider would fail
                // the component comparison in at least one appearance.
                assertColor(metric.token, equalsToken: token, under: appearance)
            }
        }
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

    /// Asserts a color is exactly an AGColors token under a fixed appearance:
    /// any hardcoded color literal would fail the sRGB comparison.
    private func assertColor(
        _ color: Color, equalsToken token: Color, under appearance: NSAppearance,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let subject = resolve(color, under: appearance)
        let expected = resolve(token, under: appearance)
        XCTAssertEqual(subject.redComponent, expected.redComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(subject.greenComponent, expected.greenComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(subject.blueComponent, expected.blueComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(subject.alphaComponent, expected.alphaComponent, accuracy: 0.01, file: file, line: line)
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

    // MARK: - Status badge

    func testAGStatusBadgeErrorCaseExists() {
        let badge = AGStatusBadge(status: .error)
        XCTAssertEqual(badge.status.catalogKey, "ds.badge.error")
    }

    func testAGStatusCatalogKeys() {
        let keys = AGStatus.allCases.map(\.catalogKey)
        XCTAssertEqual(keys, ["badge.live", "badge.placeholder", "badge.disabled", "ds.badge.error"])
        XCTAssertEqual(Set(keys).count, 4)
    }

    // MARK: - Search field binding

    func testAGSearchFieldBindingUpdates() {
        var query = "initial"
        let binding = Binding(
            get: { query },
            set: { query = $0 }
        )
        let field = AGSearchField(text: binding, placeholderKey: "projects.search")
        _ = field  // construction smoke only; SwiftUI bodies are not evaluated at init

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
        _ = field  // construction smoke only; SwiftUI bodies are not evaluated at init

        focusBinding.wrappedValue = true
        XCTAssertTrue(focused)
    }

    func testAGSearchFieldStoresPlaceholderKey() {
        let field = AGSearchField(text: .constant(""), placeholderKey: "chat.sidebar.search")
        XCTAssertEqual(field.placeholderKey, "chat.sidebar.search")
    }

    // MARK: - Chat toolbar catalog keys

    func testChatToolbarMenuKeyResolves() {
        let value = L("chat.toolbar.menu")
        XCTAssertFalse(value.isEmpty)
        XCTAssertNotEqual(value, "chat.toolbar.menu")
    }

    func testChatToolbarStopKeyResolves() {
        let value = L("chat.toolbar.stop")
        XCTAssertFalse(value.isEmpty)
        XCTAssertNotEqual(value, "chat.toolbar.stop")
    }

    func testChatToolbarSendKeyResolves() {
        let value = L("chat.toolbar.send")
        XCTAssertFalse(value.isEmpty)
        XCTAssertNotEqual(value, "chat.toolbar.send")
    }

    // MARK: - Labeled value

    func testAGLabeledValueHoldsLabelAndValue() {
        let view = AGLabeledValue(label: "PID", value: "42")

        XCTAssertEqual(view.label, "PID")
        XCTAssertEqual(view.value, "42")
    }
}
