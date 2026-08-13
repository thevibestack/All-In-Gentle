import SwiftUI
import Observation

@MainActor
@Observable
public final class AppState {
    /// Currently selected sidebar destination.
    public var selectedItem: AppTab = .projects

    /// Current scene phase, updated by the root view.
    public var scenePhase: ScenePhase = .background

    /// Global search query bound to the toolbar search field.
    public var globalSearchQuery: String = ""

    /// Whether the global search field should be focused (e.g. after ⌘K).
    public var searchFocused: Bool = false

    /// Sidebar visibility for the `NavigationSplitView` shell.
    public var sidebarVisibility: NavigationSplitViewVisibility = .all

    /// Whether the first-launch onboarding sheet should be presented.
    public var showOnboarding: Bool = true

    /// Whether the sidebar is currently collapsed.
    public var sidebarCollapsed: Bool {
        sidebarVisibility == .detailOnly
    }

    public init() {}

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
            }
        }
    }
}
