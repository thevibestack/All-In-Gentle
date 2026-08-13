import Foundation
import SwiftUI
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

    // MARK: - Sidebar destinations

    func testAllSixSidebarItemsAreDefined() {
        let items = AppState.AppTab.allCases
        XCTAssertEqual(items.map(\.rawValue), [
            "projects",
            "wiki",
            "services",
            "tokens",
            "chat",
            "sessionCleaner"
        ])
    }

    func testSidebarItemLabelsAreLocalized() {
        XCTAssertEqual(AppState.AppTab.projects.title, "Projects")
        XCTAssertEqual(AppState.AppTab.wiki.title, "Wiki")
        XCTAssertEqual(AppState.AppTab.services.title, "Services")
        XCTAssertEqual(AppState.AppTab.tokens.title, "Tokens")
        XCTAssertEqual(AppState.AppTab.chat.title, "Chat")
        XCTAssertEqual(AppState.AppTab.sessionCleaner.title, "Session Cleaner")
    }

    // MARK: - App shell state

    func testAppStateDefaults() {
        let appState = AppState()
        XCTAssertEqual(appState.selectedItem, .projects)
        XCTAssertTrue(appState.globalSearchQuery.isEmpty)
        XCTAssertFalse(appState.searchFocused)
        XCTAssertEqual(appState.sidebarVisibility, .all)
        XCTAssertTrue(appState.showOnboarding)
    }

    func testSidebarToggleFlipsVisibility() {
        let appState = AppState()
        XCTAssertEqual(appState.sidebarVisibility, .all)
        appState.toggleSidebar()
        XCTAssertEqual(appState.sidebarVisibility, .detailOnly)
        appState.toggleSidebar()
        XCTAssertEqual(appState.sidebarVisibility, .all)
    }

    // MARK: - Persistence keys

    func testOnboardingDismissedPreferenceDefaultsToFalse() {
        let store = PreferencesStore(defaults: makeEphemeralDefaults())
        XCTAssertFalse(store.bool(for: .onboardingDismissed))
    }

    func testOnboardingDismissedCanBePersisted() {
        let store = PreferencesStore(defaults: makeEphemeralDefaults())
        store.set(true, for: .onboardingDismissed)
        XCTAssertTrue(store.bool(for: .onboardingDismissed))
    }

    // MARK: - Helpers

    private func makeEphemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "smoke-tests-\(UUID().uuidString)")!
    }
}
