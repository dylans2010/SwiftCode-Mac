import Foundation

public struct iOSAppTemplate: ProjectTemplate {
    public let name = "iOS App"
    public let description = "A template for a native SwiftUI-based iOS application."
    public let icon = "iphone"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App/MyApp.swift", content: """
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
"""),
        TemplateFile(path: "Views/ContentView.swift", content: """
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
"""),
        TemplateFile(path: "Views/HomeView.swift", content: """
import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            List(1...20, id: \\.self) { item in
                Text("Item \\(item)")
            }
            .navigationTitle("Home")
        }
    }
}
"""),
        TemplateFile(path: "Views/SettingsView.swift", content: """
import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    Text("User Profile")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
""")
    ]
}
