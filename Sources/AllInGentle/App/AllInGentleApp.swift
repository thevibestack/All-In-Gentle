import SwiftUI

public struct AllInGentleApp: App {
    @State private var appState = AppState()

    public init() {}

    public var body: some Scene {
        WindowGroup("All-In-Gentle") {
            RootView()
                .environment(appState)
                .sheet(isPresented: $appState.showOnboarding) {
                    OnboardingView()
                        .environment(appState)
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .sidebar) {
                Button(L(appState.sidebarCollapsed ? "shell.showSidebar" : "shell.hideSidebar")) {
                    appState.toggleSidebar()
                }
                .keyboardShortcut("b", modifiers: .command)
                .accessibilityIdentifier("shell.menu.toggleSidebar")

                Divider()

                Button(L("shell.menu.search")) {
                    appState.searchFocused = true
                }
                .keyboardShortcut("k", modifiers: .command)
                .accessibilityIdentifier("shell.menu.search")

                Divider()

                sectionShortcutButton(item: .projects, number: 1)
                sectionShortcutButton(item: .wiki, number: 2)
                sectionShortcutButton(item: .services, number: 3)
                sectionShortcutButton(item: .tokens, number: 4)
                sectionShortcutButton(item: .chat, number: 5)
                sectionShortcutButton(item: .sessionCleaner, number: 6)
            }

            CommandGroup(replacing: .help) {
                Button(L("shell.menu.about")) {}
                    .accessibilityIdentifier("shell.menu.about")

                Button(L("shell.menu.openSource")) {}
                    .accessibilityIdentifier("shell.menu.openSource")

                Divider()

                Button(L("shell.menu.gettingStarted")) {
                    appState.presentOnboarding()
                }
                .accessibilityIdentifier("shell.menu.gettingStarted")
            }
        }

        Settings {
            AISettingsView()
                .environment(appState)
        }
    }

    private func sectionShortcutButton(item: AppState.AppTab, number: Int) -> some View {
        Button(item.title) {
            appState.selectedItem = item
            appState.sidebarVisibility = .all
        }
        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
        .accessibilityIdentifier("shell.shortcut.\(item.rawValue)")
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            if appState.sidebarCollapsed {
                detailContent
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    detailContent
                }
            }
        }
        .navigationTitle("All-In-Gentle")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(AGTypography.caption)
                        .foregroundStyle(AGColors.textSecondary)
                }
                .buttonStyle(AGButtonStyle(variant: .ghost))
                .accessibilityLabel(L(appState.sidebarCollapsed ? "shell.showSidebar" : "shell.hideSidebar"))
                .accessibilityIdentifier("shell.toolbar.toggleSidebar")
            }

            ToolbarItem(placement: .primaryAction) {
                AGSearchField(
                    text: binding(for: \.globalSearchQuery),
                    isFocused: binding(for: \.searchFocused),
                    placeholderKey: "shell.search.placeholder"
                )
                .frame(minWidth: 180, idealWidth: 240, maxWidth: 320)
                .accessibilityIdentifier("shell.searchField")
            }
        }
    }

    private var sidebar: some View {
        List(AppState.AppTab.allCases, selection: selectedItemBinding) { item in
            Label(item.title, systemImage: item.icon)
                .tag(item)
                .padding(.vertical, AGSpacing.xSmall)
                .accessibilityIdentifier("sidebar.\(item.rawValue)")
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 300)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch appState.selectedItem {
        case .projects:
            ProjectsView()
        case .wiki:
            WikiView()
        case .services:
            ServicesView()
        case .tokens:
            TokensView()
        case .chat:
            ChatView()
        case .sessionCleaner:
            SessionCleanerView()
        }
    }

    private var selectedItemBinding: Binding<AppState.AppTab?> {
        Binding(
            get: { appState.selectedItem },
            set: { appState.selectedItem = $0 ?? .projects }
        )
    }

    private func binding<T>(for keyPath: ReferenceWritableKeyPath<AppState, T>) -> Binding<T> {
        Binding(
            get: { appState[keyPath: keyPath] },
            set: { appState[keyPath: keyPath] = $0 }
        )
    }
}
