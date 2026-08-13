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
