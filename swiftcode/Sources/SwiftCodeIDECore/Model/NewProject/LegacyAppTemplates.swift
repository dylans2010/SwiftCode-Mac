// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Persistence/Templates/MacOSAppTemplate.swift
//   SwiftCode/Backend/Persistence/Templates/iOSAppTemplate.swift
//   SwiftCode/Backend/Persistence/Templates/SwiftDataAppTemplate.swift
//   (Legacy main ab03f681)
//
// Destination: SwiftCodeIDECore/Model/NewProject/LegacyAppTemplates.swift.
// Verbatim apart from this header. Each struct is one Legacy template
// file, conforming to `ProjectScaffoldTemplate` (LegacyProjectTemplates.swift
// in this directory), with the exact starter files Legacy shipped.
//
// Why these three live here instead of in the generator: the destination
// project generator (`ProjectGenerator`, ProjectGenerator+Apps.swift)
// covers the scaffold KIND — a SwiftUI app, optionally with SwiftData
// storage — but it emits a generic starter (a `TApp` + a minimal
// `ContentView`). It does NOT emit the starter content these three
// templates define:
//   * MacOSAppTemplate — NavigationSplitView app with `AppState`
//     (@Observable), `SidebarView` and `DetailView`.
//   * iOSAppTemplate — TabView app with `HomeView` (list) and
//     `SettingsView` (form).
//   * SwiftDataAppTemplate — app with an explicit `sharedModelContainer`
//     (`ModelConfiguration`, in-memory only false), `Item` model, and a
//     `ContentView` with add / delete / EditButton.
// The other 28 Legacy content templates live in LegacyProjectTemplates.swift;
// these three were left out of that file on the grounds that "the generator
// already covers" them. The kind is covered; the content above is not, so
// the templates are restored here with their Legacy names, descriptions,
// icons and files intact.
//
// Wiring hook (landing): expose the three templates wherever
// `ProjectScaffoldTemplateEngine.shared.createProject(at:template:)` is
// offered (the same surface that lists the LegacyProjectTemplates.swift
// templates), so "macOS App", "iOS App" and "SwiftData App" produce this
// starter content instead of the generic generator output.

import Foundation

public struct MacOSAppTemplate: ProjectScaffoldTemplate {
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

public struct iOSAppTemplate: ProjectScaffoldTemplate {
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

public struct SwiftDataAppTemplate: ProjectScaffoldTemplate {
    public let name = "SwiftData App"
    public let description = "A template for a SwiftUI application using SwiftData for persistence."
    public let icon = "externaldrive.fill"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App/MyApp.swift", content: """
import SwiftUI
import SwiftData

@main
struct MyApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \\(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
"""),
        TemplateFile(path: "Models/Item.swift", content: """
import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date

    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
"""),
        TemplateFile(path: "Views/ContentView.swift", content: """
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\\.modelContext) private var modelContext
    @Query private var items: [Item]

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \\(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationTitle("SwiftData Items")
            .toolbar {
                ToolbarItem() {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}
""")
    ]
}
