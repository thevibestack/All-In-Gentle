import SwiftUI

public struct AllInGentleApp: App {
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppState())
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: tabBinding) {
            ProjectsView()
                .tabItem { Label(L("tab.projects"), systemImage: "folder") }
                .tag(AppState.AppTab.projects)

            WikiView()
                .tabItem { Label(L("tab.wiki"), systemImage: "books.vertical") }
                .tag(AppState.AppTab.wiki)

            ServicesView()
                .tabItem { Label(L("tab.services"), systemImage: "checkmark.shield") }
                .tag(AppState.AppTab.services)

            TokensView()
                .tabItem { Label(L("tab.tokens"), systemImage: "chart.bar") }
                .tag(AppState.AppTab.tokens)

            ChatView()
                .tabItem { Label(L("tab.chat"), systemImage: "bubble.left.and.bubble.right") }
                .tag(AppState.AppTab.chat)

            SessionCleanerView()
                .tabItem { Label(L("tab.sessionCleaner"), systemImage: "trash") }
                .tag(AppState.AppTab.sessionCleaner)
        }
        .onChange(of: scenePhase) { _, newPhase in
            appState.scenePhase = newPhase
        }
    }

    private var tabBinding: Binding<AppState.AppTab> {
        Binding(
            get: { appState.selectedTab },
            set: { appState.selectedTab = $0 }
        )
    }
}