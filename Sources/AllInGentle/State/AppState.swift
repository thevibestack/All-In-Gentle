import SwiftUI
import Observation

@MainActor
@Observable
public final class AppState {
    public var selectedTab: AppTab = .projects
    public var scenePhase: ScenePhase = .background

    public init() {}

    public enum AppTab: String, CaseIterable, Identifiable, Sendable {
        case projects
        case wiki
        case services
        case tokens
        case chat
        case sessionCleaner

        public var id: String { rawValue }

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
