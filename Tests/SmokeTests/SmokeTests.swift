import Foundation
import XCTest
@testable import AllInGentleKit

final class SmokeTests: XCTestCase {
    // MARK: - Interaction-state badges

    func testInteractionStateCatalogKeys() {
        XCTAssertEqual(InteractionState.live.catalogKey, "badge.live")
        XCTAssertEqual(InteractionState.placeholder.catalogKey, "badge.placeholder")
        XCTAssertEqual(InteractionState.disabled.catalogKey, "badge.disabled")
    }

    func testInteractionStateBadgeLabels() {
        XCTAssertEqual(InteractionState.live.label, "Live")
        XCTAssertEqual(InteractionState.placeholder.label, "Coming soon")
        XCTAssertEqual(InteractionState.disabled.label, "Disabled")
    }

    func testPlaceholderBadgeCanBeConstructed() {
        let badge = InteractionStateBadge(state: .placeholder)
        XCTAssertNotNil(badge)
    }

    // MARK: - App tabs

    func testAllSixTabsAreDefined() {
        let tabs = AppState.AppTab.allCases
        XCTAssertEqual(tabs.map(\.rawValue), [
            "projects",
            "wiki",
            "services",
            "tokens",
            "chat",
            "sessionCleaner"
        ])
    }

    func testTabTitlesAreLocalized() {
        XCTAssertEqual(AppState.AppTab.projects.title, "Projects")
        XCTAssertEqual(AppState.AppTab.wiki.title, "Wiki")
        XCTAssertEqual(AppState.AppTab.services.title, "Services")
        XCTAssertEqual(AppState.AppTab.tokens.title, "Tokens")
        XCTAssertEqual(AppState.AppTab.chat.title, "Chat")
        XCTAssertEqual(AppState.AppTab.sessionCleaner.title, "Session Cleaner")
    }
}
