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
    }
}
