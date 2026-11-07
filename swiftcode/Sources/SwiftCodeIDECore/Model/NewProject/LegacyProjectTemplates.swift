import Foundation

public actor ProjectScaffoldTemplateEngine {
    public static let shared = ProjectScaffoldTemplateEngine()

    public func createProject(at url: URL, template: any ProjectScaffoldTemplate) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for file in template.files {
            let fileURL = url.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}

public protocol ProjectScaffoldTemplate: Sendable {
    var name: String { get }
    var description: String { get }
    var icon: String { get }
    var files: [TemplateFile] { get }
}

public struct TemplateFile: Sendable {
    public let path: String
    public let content: String
}

public struct AnalyticsDashboardViewTemplate: ProjectScaffoldTemplate {
    public let name = "Analytics Dashboard"
    public let description = "A detailed business analytics console with activity logs, filters, and charts."
    public let icon = "chart.bar.xaxis"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct AnalyticsApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack {\n            Text(\"Sales Analytics\").font(.title.bold())\n            Image(systemName: \"chart.bar.fill\").font(.system(size: 100)).foregroundStyle(.orange)\n        }\n        .padding()\n    }\n}")
    ]
}

public struct AudioPlayerViewTemplate: ProjectScaffoldTemplate {
    public let name = "Audio Player"
    public let description = "A slick music and podcast deck with play/pause controls, seek timelines, and album artwork."
    public let icon = "play.circle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct AudioApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(spacing: 24) {\n            Image(systemName: \"music.note\").font(.system(size: 80)).padding(40).background(Color.orange.opacity(0.1)).cornerRadius(20)\n            Text(\"Now Playing\").font(.headline)\n            HStack(spacing: 32) {\n                Image(systemName: \"backward.fill\")\n                Image(systemName: \"play.fill\").font(.largeTitle)\n                Image(systemName: \"forward.fill\")\n            }\n        }\n        .padding()\n    }\n}")
    ]
}

public struct BudgetTrackerViewTemplate: ProjectScaffoldTemplate {
    public let name = "Budget Tracker"
    public let description = "A cashbook manager plotting monthly transactions, balance logs, and saving goals."
    public let icon = "dollarsign.circle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct BudgetApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(spacing: 16) {\n            Text(\"Current Balance\").font(.headline)\n            Text(\"$5,240.00\").font(.system(size: 40, weight: .bold))\n        }\n        .padding()\n    }\n}")
    ]
}

public struct CalculatorViewTemplate: ProjectScaffoldTemplate {
    public let name = "Calculator View"
    public let description = "A simple mathematical utility grid with number inputs and operators."
    public let icon = "divide.circle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct CalculatorApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(spacing: 12) {\n            Text(\"0\").font(.system(size: 48)).frame(maxWidth: .infinity, alignment: .trailing).padding()\n            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {\n                ForEach([\"7\",\"8\",\"9\",\"/\",\"4\",\"5\",\"6\",\"*\",\"1\",\"2\",\"3\",\"-\",\"0\",\".\",\"=\",\"+\"], id: \\.self) { btn in\n                    Text(btn).font(.title).frame(width: 48, height: 48).background(Color.secondary.opacity(0.15)).cornerRadius(10)\n                }\n            }\n        }\n        .frame(width: 240)\n        .padding()\n    }\n}")
    ]
}

public struct CalendarViewTemplate: ProjectScaffoldTemplate {
    public let name = "Calendar View"
    public let description = "A calendar grid showing dates, monthly views, events timeline, and planner slots."
    public let icon = "calendar"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct CalendarApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack {\n            Text(\"October 2026\").font(.title.bold())\n            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {\n                ForEach(1...31, id: \\.self) { day in\n                    Text(\"\\(day)\")\n                        .frame(width: 32, height: 32)\n                        .background(day == 15 ? Color.orange : Color.clear)\n                        .foregroundColor(day == 15 ? .white : .primary)\n                        .clipShape(Circle())\n                }\n            }\n            .padding()\n        }\n    }\n}")
    ]
}

public struct ChatViewTemplate: ProjectScaffoldTemplate {
    public let name = "Chat View"
    public let description = "An interactive messaging UI with conversational message bubbles, dynamic input bar, and auto-scroll."
    public let icon = "message"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct ChatApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    @State private var text = \"\"\n    var body: some View {\n        VStack {\n            ScrollView {\n                VStack(alignment: .leading, spacing: 12) {\n                    Text(\"Hey, how is it going?\").padding().background(Color.blue.opacity(0.1)).cornerRadius(10)\n                    Text(\"Everything is great, working on SwiftCode!\").padding().background(Color.gray.opacity(0.1)).cornerRadius(10)\n                }\n                .padding()\n            }\n            HStack {\n                TextField(\"Message\", text: $text).textFieldStyle(.roundedBorder)\n                Button(\"Send\") {}\n            }\n            .padding()\n        }\n    }\n}")
    ]
}

public struct DashboardViewTemplate: ProjectScaffoldTemplate {
    public let name = "Dashboard View"
    public let description = "A high-density dashboard with stat cards, metrics charts, and recent activity feeds."
    public let icon = "chart.layout.gauge"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct DashboardApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        ScrollView {\n            VStack(spacing: 20) {\n                Text(\"My Dashboard\").font(.largeTitle.bold())\n                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {\n                    ForEach(0..<4) { i in\n                        VStack(alignment: .leading) {\n                            Text(\"Metric \\(i+1)\").font(.caption).foregroundStyle(.secondary)\n                            Text(\"\\(100 * (i+1))\").font(.title.bold())\n                        }\n                        .padding()\n                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))\n                    }\n                }\n            }\n            .padding()\n        }\n    }\n}")
    ]
}

public struct DrawingViewTemplate: ProjectScaffoldTemplate {
    public let name = "Drawing View"
    public let description = "A canvas template with drawing pencils, brush sliders, and a full color palette palette selection."
    public let icon = "scribble"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct DrawingApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack {\n            Text(\"Drawing Canvas\").font(.headline).padding()\n            Spacer()\n            Image(systemName: \"pencil.and.outline\").font(.system(size: 64))\n            Spacer()\n        }\n    }\n}")
    ]
}

public struct ECommerceViewTemplate: ProjectScaffoldTemplate {
    public let name = "E-Commerce View"
    public let description = "A product listing and showcase catalog with product detail cards and shopping cart actions."
    public let icon = "cart"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct ECommerceApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        ScrollView {\n            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {\n                ForEach(1...6, id: \\.self) { i in\n                    VStack(alignment: .leading, spacing: 8) {\n                        Image(systemName: \"tag\").font(.largeTitle)\n                        Text(\"Product \\(i)\").font(.headline)\n                        Text(\"$99.99\").font(.subheadline).foregroundStyle(.secondary)\n                    }\n                    .padding()\n                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))\n                }\n            }\n            .padding()\n        }\n    }\n}")
    ]
}

public struct FileBrowserViewTemplate: ProjectScaffoldTemplate {
    public let name = "File Browser"
    public let description = "A Finder-like storage directory navigator displaying file lists and path history links."
    public let icon = "folder.circle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct FileApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        List {\n            Label(\"Documents\", systemImage: \"folder\")\n            Label(\"Downloads\", systemImage: \"folder\")\n            Label(\"project.json\", systemImage: \"doc.text\")\n        }\n    }\n}")
    ]
}

public struct FitnessTrackerViewTemplate: ProjectScaffoldTemplate {
    public let name = "Fitness Tracker"
    public let description = "A sports monitoring suite tracking workout metrics, step counters, and visual activity rings."
    public let icon = "figure.run"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct FitnessApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(alignment: .leading, spacing: 20) {\n            Text(\"Activity\").font(.largeTitle.bold())\n            HStack {\n                Label(\"10,420 Steps\", systemImage: \"shoeprints.fill\")\n                Spacer()\n                Label(\"420 kcal\", systemImage: \"flame.fill\")\n            }\n            .font(.headline)\n        }\n        .padding()\n    }\n}")
    ]
}

public struct IntroductionTemplate: ProjectScaffoldTemplate {
    public let name = "Introduction to SwiftCode"
    public let description = "A guided tour of SwiftCode's features and capabilities."
    public let icon = "hand.wave"
    public let files: [TemplateFile] = [
        TemplateFile(path: "Welcome.swift", content: """
//
//  Welcome to SwiftCode
//
//  This project is designed to help you get started with the SwiftCode IDE.
//

import SwiftUI

struct WelcomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header

                featuresSection

                gettingStartedSection

                footer
            }
            .padding(40)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "swift")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Welcome to SwiftCode")
                .font(.system(size: 40, weight: .bold))

            Text("The Next Generation IDE for Swift and SwiftUI development on macOS.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Key Features")
                .font(.title2)
                .bold()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 20) {
                FeatureCard(
                    icon: "sidebar.left",
                    title: "Advanced Sidebar",
                    description: "Navigate your project, search code, and manage git with ease."
                )

                FeatureCard(
                    icon: "play.circle",
                    title: "Local Simulation",
                    description: "Run and preview your SwiftUI views instantly without full builds."
                )

                FeatureCard(
                    icon: "sparkles",
                    title: "AI Assistance",
                    description: "Get smart suggestions and chat with an AI that understands your code."
                )

                FeatureCard(
                    icon: "hammer",
                    title: "Developer Tools",
                    description: "A vast collection of utilities for debugging and performance tuning."
                )
            }
        }
    }

    private var gettingStartedSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Getting Started")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 10) {
                StepRow(number: 1, text: "Explore the project navigator on the left.")
                StepRow(number: 2, text: "Try editing this file and see syntax highlighting in action.")
                StepRow(number: 3, text: "Open the AI Assistant to ask questions about your code.")
                StepRow(number: 4, text: "Use the 'Run' button in the toolbar to simulate your app.")
            }
        }
    }

    private var footer: some View {
        Text("Happy Coding!")
            .font(.headline)
            .foregroundStyle(.orange)
            .padding(.top, 20)
    }
}

struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.accent)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
}

struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 15) {
            Text("\\(number)")
                .font(.subheadline)
                .bold()
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .font(.body)
        }
    }
}

#Preview {
    WelcomeView()
}
"""),
        TemplateFile(path: "Features/EditorTips.swift", content: """
import SwiftUI

// TIP: Use ⌘S to save your work at any time.
// TIP: Use ⌘F to find text within the current file.
// TIP: Use ⌘⇧N to create a new project.

struct EditorTips: View {
    var body: some View {
        List {
            Label("Syntax Highlighting", systemImage: "paintbrush")
            Label("Code Completion", systemImage: "text.cursor")
            Label("Multi-tab Support", systemImage: "menubar.dock.rectangle")
        }
        .navigationTitle("Editor Features")
    }
}
""")
    ]
}

public struct LoginViewTemplate: ProjectScaffoldTemplate {
    public let name = "Login View"
    public let description = "A polished user authentication template with email/password fields, validation, and social login options."
    public let icon = "lock.shield"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct LoginApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    @State private var email = \"\"\n    @State private var password = \"\"\n    var body: some View {\n        VStack(spacing: 20) {\n            Image(systemName: \"person.circle.fill\").font(.system(size: 80)).foregroundStyle(.blue)\n            TextField(\"Email\", text: $email).textFieldStyle(.roundedBorder)\n            SecureField(\"Password\", text: $password).textFieldStyle(.roundedBorder)\n            Button(\"Sign In\") {}.buttonStyle(.borderedProminent).controlSize(.large)\n        }\n        .padding(40)\n        .frame(width: 320)\n    }\n}")
    ]
}

public struct MapViewTemplate: ProjectScaffoldTemplate {
    public let name = "Map View"
    public let description = "A MapKit template highlighting locations, custom pin selectors, and route search forms."
    public let icon = "map"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct MapApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\nimport MapKit\n\nstruct ContentView: View {\n    var body: some View {\n        VStack {\n            Text(\"Interactive Map\").font(.headline).padding()\n            Map()\n                .frame(maxWidth: .infinity, maxHeight: .infinity)\n        }\n    }\n}")
    ]
}

public struct MarkdownEditorViewTemplate: ProjectScaffoldTemplate {
    public let name = "Markdown Editor"
    public let description = "A markdown document space with side-by-side editing text fields and live rendering html templates."
    public let icon = "doc.plaintext"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct MarkdownApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    @State private var text = \"# Hello World\\nStart writing...\"\n    var body: some View {\n        HStack {\n            TextEditor(text: $text)\n            Divider()\n            VStack(alignment: .leading) {\n                Text(\"Preview\").font(.headline)\n                Text(text)\n            }\n            .frame(maxWidth: .infinity, alignment: .topLeading)\n        }\n        .padding()\n    }\n}")
    ]
}

public struct NewsReaderViewTemplate: ProjectScaffoldTemplate {
    public let name = "News Reader"
    public let description = "A stylized publication magazine featuring article rows, bookmark selectors, and fluid readers."
    public let icon = "newspaper"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct NewsApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        List {\n            ForEach(1...3, id: \\.self) { i in\n                VStack(alignment: .leading, spacing: 6) {\n                    Text(\"Breaking News Article \\(i)\").font(.headline)\n                    Text(\"This is a preview of the news article content.\").font(.subheadline).foregroundStyle(.secondary)\n                }\n                .padding(.vertical, 4)\n            }\n        }\n    }\n}")
    ]
}

public struct NotesViewTemplate: ProjectScaffoldTemplate {
    public let name = "Notes View"
    public let description = "A modern notes app workspace with category lists, title search, and full rich-text note editor views."
    public let icon = "note.text"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct NotesApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    @State private var notes = [\"Idea 1\", \"Shopping List\", \"SwiftCode Review\"]\n    var body: some View {\n        NavigationSplitView {\n            List(notes, id: \\.self) { note in\n                Text(note)\n            }\n        } detail: {\n            Text(\"Select a note\")\n        }\n    }\n}")
    ]
}

public struct OnboardingViewTemplate: ProjectScaffoldTemplate {
    public let name = "Onboarding View"
    public let description = "A multi-page step-through splash tutorial sequence with sliding transitions and CTA landing button."
    public let icon = "sparkles"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct OnboardingApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        TabView {\n            VStack(spacing: 20) {\n                Image(systemName: \"macbook.and.iphone\").font(.system(size: 80))\n                Text(\"Welcome\").font(.title.bold())\n                Text(\"Learn how to use SwiftCode efficiently.\")\n            }\n            VStack(spacing: 20) {\n                Image(systemName: \"bolt.fill\").font(.system(size: 80))\n                Text(\"Blazing Fast\").font(.title.bold())\n                Text(\"Engineered for native performance.\")\n            }\n        }\n        .tabViewStyle(.page)\n        .frame(width: 400, height: 300)\n    }\n}")
    ]
}

public struct PhotoGalleryViewTemplate: ProjectScaffoldTemplate {
    public let name = "Photo Gallery"
    public let description = "A full-window photo collection showcase with interactive album list selectors."
    public let icon = "photo.on.rectangle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct PhotoApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        ScrollView {\n            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {\n                ForEach(1...12, id: \\.self) { i in\n                    Image(systemName: \"photo\")\n                        .font(.system(size: 40))\n                        .frame(width: 100, height: 100)\n                        .background(Color.secondary.opacity(0.1))\n                        .cornerRadius(12)\n                }\n            }\n            .padding()\n        }\n    }\n}")
    ]
}

public struct ProfileViewTemplate: ProjectScaffoldTemplate {
    public let name = "Profile View"
    public let description = "A premium user dashboard with user bio, avatar editor, preferences tabs, and stats indicators."
    public let icon = "person.crop.circle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct ProfileApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(spacing: 16) {\n            Image(systemName: \"person.circle.fill\").font(.system(size: 72))\n            Text(\"Developer User\").font(.title2.bold())\n            Text(\"macOS Systems Engineer\").foregroundStyle(.secondary)\n        }\n        .padding()\n    }\n}")
    ]
}

public struct QuizViewTemplate: ProjectScaffoldTemplate {
    public let name = "Quiz App"
    public let description = "A learning quiz card space displaying question cards, selectable choices, and final score decks."
    public let icon = "questionmark.bubble"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct QuizApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(spacing: 20) {\n            Text(\"Question 1 of 10\").font(.caption)\n            Text(\"What is the latest Swift version?\").font(.title2.bold())\n            Button(\"Swift 5\") {}.buttonStyle(.bordered).frame(maxWidth: .infinity)\n            Button(\"Swift 6\") {}.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)\n        }\n        .padding()\n    }\n}")
    ]
}

public struct RecipeViewTemplate: ProjectScaffoldTemplate {
    public let name = "Recipe App"
    public let description = "A kitchen assistant listing culinary instructions, cooking times, and step-by-step guidance."
    public let icon = "fork.knife"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct RecipeApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(alignment: .leading, spacing: 12) {\n            Text(\"Spaghetti Carbonara\").font(.largeTitle.bold())\n            Text(\"Prep: 15 mins | Cook: 10 mins\").font(.subheadline).foregroundStyle(.secondary)\n        }\n        .padding()\n    }\n}")
    ]
}

public struct SettingsViewTemplate: ProjectScaffoldTemplate {
    public let name = "Settings View"
    public let description = "A standard macOS-style multi-pane preferences interface with toggles, sliders, and picker controls."
    public let icon = "gearshape"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct SettingsApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    @State private var notificationsEnabled = true\n    @State private var themeSelection = \"Dark\"\n    var body: some View {\n        Form {\n            Toggle(\"Enable Notifications\", isOn: $notificationsEnabled)\n            Picker(\"Theme\", selection: $themeSelection) {\n                Text(\"Light\").tag(\"Light\")\n                Text(\"Dark\").tag(\"Dark\")\n            }\n        }\n        .padding()\n    }\n}")
    ]
}

public struct TaskBoardViewTemplate: ProjectScaffoldTemplate {
    public let name = "Task Board"
    public let description = "A Kanban timeline manager with lanes, drag handles, and priority chips."
    public let icon = "columns.3"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct BoardApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        HStack(spacing: 16) {\n            VStack(alignment: .leading) {\n                Text(\"To Do\").font(.headline)\n                Text(\"Task A\").padding().background(Color.secondary.opacity(0.1)).cornerRadius(8)\n            }\n            VStack(alignment: .leading) {\n                Text(\"In Progress\").font(.headline)\n                Text(\"Task B\").padding().background(Color.secondary.opacity(0.1)).cornerRadius(8)\n            }\n        }\n        .padding()\n    }\n}")
    ]
}

public struct TodoViewTemplate: ProjectScaffoldTemplate {
    public let name = "Todo View"
    public let description = "A checklist with category categorization, smart completion states, and progress bar trackers."
    public let icon = "checklist"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct TodoApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    @State private var items = [\"Code Swift 6\", \"Ship features\", \"Drink water\"]\n    var body: some View {\n        List(items, id: \\.self) { item in\n            Label(item, systemImage: \"circle\")\n        }\n        .navigationTitle(\"To-do List\")\n    }\n}")
    ]
}

public struct WeatherViewTemplate: ProjectScaffoldTemplate {
    public let name = "Weather View"
    public let description = "A detailed dashboard displaying current conditions, hourly forecasts, and 10-day trends."
    public let icon = "cloud.sun"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct WeatherApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        VStack(spacing: 20) {\n            Text(\"San Francisco\").font(.largeTitle)\n            Text(\"68°\").font(.system(size: 80, weight: .thin))\n            Text(\"Partly Cloudy\").font(.headline).foregroundStyle(.secondary)\n        }\n        .padding()\n    }\n}")
    ]
}

public struct MenuBarAppTemplate: ProjectScaffoldTemplate {
    public let name = "Menu Bar App"
    public let description = "A macOS application that resides primarily in the menu bar."
    public let icon = "menubar.rectangle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct MenuBarApp: App {\n    var body: some Scene {\n        MenuBarExtra(\"My App\", systemImage: \"star\") {\n            Button(\"Quit\") {\n                NSApplication.shared.terminate(nil)\n            }\n        }\n    }\n}")
    ]
}

public struct SystemExtensionTemplate: ProjectScaffoldTemplate {
    public let name = "System Extension"
    public let description = "A template for creating a macOS system extension (e.g., Network Extension)."
    public let icon = "puzzlepiece"
    public let files: [TemplateFile] = [
        TemplateFile(path: "main.swift", content: "import Foundation\nimport SystemExtensions\n\nclass ExtensionDelegate: NSObject, OSSystemExtensionRequestDelegate {\n    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {}\n    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {}\n}")
    ]
}


public struct CommandLineToolTemplate: ProjectScaffoldTemplate {
    public let name = "Command Line Tool"
    public let description = "A template for a command-line utility."
    public let icon = "terminal"
    public let files: [TemplateFile] = [
        TemplateFile(path: "main.swift", content: "import Foundation\n\nprint(\"Hello, World!\")")
    ]
    public init() {}
}

public struct DocumentAppTemplate: ProjectScaffoldTemplate {
    public let name = "Document App"
    public let description = "A document-based app for macOS."
    public let icon = "doc.text"
    public let files: [TemplateFile] = [
        TemplateFile(path: "Document.swift", content: "import SwiftUI\nimport UniformTypeIdentifiers\n\nstruct MyDocument: FileDocument {\n    var text: String\n    init(text: String = \"\") { self.text = text }\n    static var readableContentTypes: [UTType] { [.plainText] }\n    init(configuration: ReadConfiguration) throws {\n        guard let data = configuration.file.contents,\n              let string = String(data: data, encoding: .utf8)\n        else { throw CocoaError(.fileReadCorruptFile) }\n        text = string\n    }\n    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {\n        Data(text.utf8).makeFileWrapper()\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    @Binding var document: MyDocument\n    var body: some View {\n        TextEditor(text: $document.text)\n    }\n}"),
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct DocumentApp: App {\n    var body: some Scene {\n        DocumentGroup(newDocument: MyDocument()) { file in\n            ContentView(document: file.$document)\n        }\n    }\n}")
    ]
    public init() {}
}

public struct FrameworkTemplate: ProjectScaffoldTemplate {
    public let name = "Framework"
    public let description = "A template for a shared framework."
    public let icon = "briefcase"
    public let files: [TemplateFile] = [
        TemplateFile(path: "MyFramework.swift", content: "import Foundation\n\npublic class MyFramework {\n    public init() {}\n}")
    ]
    public init() {}
}

public struct GameMetalTemplate: ProjectScaffoldTemplate {
    public let name = "Metal Game"
    public let description = "A high-performance game template using the Metal framework."
    public let icon = "cpu"
    public let files: [TemplateFile] = [
        TemplateFile(path: "Renderer.swift", content: "import Metal\nimport MetalKit\n\nclass Renderer: NSObject, MTKViewDelegate {\n    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}\n    func draw(in view: MTKView) {\n        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }\n    }\n}"),
        TemplateFile(path: "GameViewController.swift", content: "import AppKit\nimport MetalKit\n\nclass GameViewController: NSViewController {\n    var renderer: Renderer!\n    override func viewDidLoad() {\n        super.viewDidLoad()\n        let mtkView = view as! MTKView\n        mtkView.device = MTLCreateSystemDefaultDevice()\n        renderer = Renderer()\n        mtkView.delegate = renderer\n    }\n}")
    ]
    public init() {}
}

public struct GameSpriteKitTemplate: ProjectScaffoldTemplate {
    public let name = "SpriteKit Game"
    public let description = "A 2D game template using the SpriteKit framework."
    public let icon = "gamecontroller"
    public let files: [TemplateFile] = [
        TemplateFile(path: "GameScene.swift", content: "import SpriteKit\n\nclass GameScene: SKScene {\n    override func didMove(to view: SKView) {\n        let label = SKLabelNode(text: \"Hello SpriteKit!\")\n        addChild(label)\n    }\n}"),
        TemplateFile(path: "AppDelegate.swift", content: "import AppKit\nimport SpriteKit\n\n@main\nclass AppDelegate: NSObject, NSApplicationDelegate {\n    func applicationDidFinishLaunching(_ notification: Notification) {}\n}")
    ]
    public init() {}
}

public struct MultiplatformAppTemplate: ProjectScaffoldTemplate {
    public let name = "Multiplatform App"
    public let description = "A SwiftUI app that runs on macOS, iOS, and visionOS."
    public let icon = "square.on.square"
    public let files: [TemplateFile] = [
        TemplateFile(path: "Shared/ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        Text(\"Multiplatform App\")\n    }\n}"),
        TemplateFile(path: "Shared/App.swift", content: "import SwiftUI\n\n@main\nstruct MultiApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}")
    ]
    public init() {}
}

public struct SafariExtensionTemplate: ProjectScaffoldTemplate {
    public let name = "Safari Extension"
    public let description = "A template for a Safari web extension."
    public let icon = "safari"
    public let files: [TemplateFile] = [
        TemplateFile(path: "manifest.json", content: "{\n    \"manifest_version\": 3,\n    \"name\": \"My Extension\",\n    \"version\": \"1.0\"\n}"),
        TemplateFile(path: "background.js", content: "console.log(\"Background script running\");")
    ]
    public init() {}
}

public struct StaticLibraryTemplate: ProjectScaffoldTemplate {
    public let name = "Static Library"
    public let description = "A template for a static library (.a)."
    public let icon = "building.columns"
    public let files: [TemplateFile] = [
        TemplateFile(path: "Library.swift", content: "import Foundation\n\npublic class MyStaticLibrary {\n    public init() {}\n}")
    ]
    public init() {}
}

public struct SwiftMacroTemplate: ProjectScaffoldTemplate {
    public let name = "Swift Macro"
    public let description = "A template for creating a Swift Macro library."
    public let icon = "wand.and.stars"
    public let files: [TemplateFile] = [
        TemplateFile(path: "MyMacro.swift", content: "import Foundation\n\npublic struct MyMacro {\n    public init() {}\n}")
    ]
    public init() {}
}

public struct SwiftPackageTemplate: ProjectScaffoldTemplate {
    public let name = "Swift Package"
    public let description = "A template for a Swift package, suitable for libraries and tools."
    public let icon = "shippingbox"
    public let files: [TemplateFile] = [
        TemplateFile(path: "Package.swift", content: "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n    name: \"MyPackage\",\n    targets: [\n        .target(name: \"MyPackage\"),\n    ]\n)"),
        TemplateFile(path: "Sources/MyPackage/MyPackage.swift", content: "public struct MyPackage {\n    public init() {}\n}")
    ]
    public init() {}
}

extension ProjectTemplateCatalog {
    public static let scaffoldTemplates: [any ProjectScaffoldTemplate] = [
        AnalyticsDashboardViewTemplate(),
        AudioPlayerViewTemplate(),
        BudgetTrackerViewTemplate(),
        CalculatorViewTemplate(),
        CalendarViewTemplate(),
        ChatViewTemplate(),
        DashboardViewTemplate(),
        DrawingViewTemplate(),
        ECommerceViewTemplate(),
        FileBrowserViewTemplate(),
        FitnessTrackerViewTemplate(),
        IntroductionTemplate(),
        LoginViewTemplate(),
        MapViewTemplate(),
        MarkdownEditorViewTemplate(),
        NewsReaderViewTemplate(),
        NotesViewTemplate(),
        OnboardingViewTemplate(),
        PhotoGalleryViewTemplate(),
        ProfileViewTemplate(),
        QuizViewTemplate(),
        RecipeViewTemplate(),
        SettingsViewTemplate(),
        TaskBoardViewTemplate(),
        TodoViewTemplate(),
        WeatherViewTemplate(),
        MenuBarAppTemplate(),
        SystemExtensionTemplate(),
        CommandLineToolTemplate(),
        DocumentAppTemplate(),
        FrameworkTemplate(),
        GameMetalTemplate(),
        GameSpriteKitTemplate(),
        MultiplatformAppTemplate(),
        SafariExtensionTemplate(),
        StaticLibraryTemplate(),
        SwiftMacroTemplate(),
        SwiftPackageTemplate()
    ]

    public static func scaffoldTemplate(named name: String) -> (any ProjectScaffoldTemplate)? {
        scaffoldTemplates.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

