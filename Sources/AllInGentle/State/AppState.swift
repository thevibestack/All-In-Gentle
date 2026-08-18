import SwiftUI
import Observation

@MainActor
@Observable
public final class AppState {
    /// Currently selected sidebar destination.
    public var selectedItem: AppTab = .dashboard

    /// Currently selected project path for cross-tab context.
    public var selectedProjectPath: String? = nil {
        didSet {
            if let selectedProjectPath {
                preferences.set(selectedProjectPath, for: .lastProjectPath)
            } else {
                preferences.removeValue(for: .lastProjectPath)
            }
        }
    }

    /// Global search query bound to the toolbar search field.
    public var globalSearchQuery: String = ""

    /// Whether the global search field should be focused (e.g. after ⌘K).
    public var searchFocused: Bool = false

    /// Sidebar visibility for the `NavigationSplitView` shell.
    public var sidebarVisibility: NavigationSplitViewVisibility = .all

    /// Whether the first-launch onboarding sheet should be presented.
    public var showOnboarding: Bool

    private let preferences: PreferencesStore

    public init(
        preferences: PreferencesStore = PreferencesStore(),
        migrator: ProviderConfigurationMigrator? = nil
    ) {
        self.preferences = preferences
        self.showOnboarding = !(preferences.bool(for: .onboardingDismissed) || preferences.onboardingCompleted)
        self.selectedProjectPath = preferences.string(for: .lastProjectPath)

        let migration =
            migrator
            ?? ProviderConfigurationMigrator(
                preferences: preferences,
                keychain: KeychainStore()
            )
        Task {
            await migration.migrateIfNeeded()
        }
    }

    /// Dismiss the onboarding sheet and persist the choice.
    public func dismissOnboarding() {
        showOnboarding = false
        preferences.set(true, for: .onboardingDismissed)
        preferences.onboardingCompleted = true
    }

    /// Reopen the onboarding sheet for help menu.
    public func presentOnboarding() {
        showOnboarding = true
    }

    /// Whether the sidebar is currently collapsed.
    public var sidebarCollapsed: Bool {
        sidebarVisibility == .detailOnly
    }

    /// Toggle the sidebar between fully visible and detail-only.
    public func toggleSidebar() {
        sidebarVisibility = sidebarCollapsed ? .all : .detailOnly
    }

    public enum AppTab: String, CaseIterable, Identifiable, Sendable {
        case projects
        case wiki
        case services
        case tokens
        case chat
        case sessionCleaner
        case dashboard

        public var id: String { rawValue }

        public init?(id: String) {
            self.init(rawValue: id)
        }

        public var titleKey: String {
            "tab.\(rawValue)"
        }

        public var title: String {
            L(titleKey)
        }

        public var icon: String {
            switch self {
            case .projects:
                return "folder"
            case .wiki:
                return "books.vertical"
            case .services:
                return "checkmark.shield"
            case .tokens:
                return "chart.bar"
            case .chat:
                return "bubble.left.and.bubble.right"
            case .sessionCleaner:
                return "trash"
            case .dashboard:
                return "gauge"
            }
        }
    }
}
