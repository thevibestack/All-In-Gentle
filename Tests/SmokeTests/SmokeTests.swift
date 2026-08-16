import Foundation
import SwiftUI
import XCTest
@testable import AllInGentleKit

@MainActor
final class SmokeTests: XCTestCase {
    // MARK: - Sidebar destinations

    func testAllSixSidebarItemsAreDefined() {
        let items = AppState.AppTab.allCases
        XCTAssertEqual(
            items.map(\.rawValue),
            [
                "projects",
                "wiki",
                "services",
                "tokens",
                "chat",
                "sessionCleaner",
            ])
    }

    func testSidebarItemLabelsAreLocalized() {
        for item in AppState.AppTab.allCases {
            XCTAssertEqual(item.title, L(item.titleKey))
            XCTAssertFalse(item.title.isEmpty)
        }
    }

    // MARK: - App shell state

    // MARK: - Onboarding

    func testOnboardingViewCanBeConstructed() {
        let view = OnboardingView()
        XCTAssertNotNil(view)
    }

    func testAppStateDismissOnboardingPersists() {
        let defaults = makeEphemeralDefaults()
        let store = PreferencesStore(defaults: defaults)
        let appState = AppState(preferences: store)
        XCTAssertTrue(appState.showOnboarding)

        appState.dismissOnboarding()
        XCTAssertFalse(appState.showOnboarding)
        XCTAssertTrue(store.bool(for: .onboardingDismissed))
    }

    func testAppStateReadsDismissedOnboarding() {
        let defaults = makeEphemeralDefaults()
        let store = PreferencesStore(defaults: defaults)
        store.set(true, for: .onboardingDismissed)

        let appState = AppState(preferences: store)
        XCTAssertFalse(appState.showOnboarding)
    }

    func testAppStatePresentOnboarding() {
        let defaults = makeEphemeralDefaults()
        let store = PreferencesStore(defaults: defaults)
        store.set(true, for: .onboardingDismissed)

        let appState = AppState(preferences: store)
        XCTAssertFalse(appState.showOnboarding)
        appState.presentOnboarding()
        XCTAssertTrue(appState.showOnboarding)
    }

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
