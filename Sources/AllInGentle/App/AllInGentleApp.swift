import SwiftUI

public struct AllInGentleApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AppState())
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("All-In-Gentle")
    }
}