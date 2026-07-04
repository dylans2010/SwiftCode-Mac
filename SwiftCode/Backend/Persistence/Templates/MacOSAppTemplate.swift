import Foundation

public struct MacOSAppTemplate: ProjectTemplate {
    public let name = "macOS App"
    public let description = "A template for a native SwiftUI-based macOS application with a standard architecture."
    public let icon = "desktopcomputer"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App/MyApp.swift", content: """
import SwiftUI

@main
struct MyApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
    }
}
"""),
        TemplateFile(path: "Views/ContentView.swift", content: """
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
    }
}
"""),
        TemplateFile(path: "Views/SidebarView.swift", content: """
import SwiftUI

struct SidebarView: View {
    var body: some View {
        List {
            NavigationLink(value: "Home") {
                Label("Home", systemImage: "house")
            }
            NavigationLink(value: "Settings") {
                Label("Settings", systemImage: "gear")
            }
        }
        .navigationTitle("Sidebar")
    }
}
"""),
        TemplateFile(path: "Views/DetailView.swift", content: """
import SwiftUI

struct DetailView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Welcome to your macOS App!")
                .font(.title)
        }
        .padding()
    }
}
"""),
        TemplateFile(path: "Models/AppState.swift", content: """
import Foundation
import Observation

@Observable
class AppState {
    var title: String = "My macOS App"
    var isConfigured: Bool = false
}
"""),
        TemplateFile(path: "Resources/Assets.xcassets/Contents.json", content: """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
""")
    ]
}
