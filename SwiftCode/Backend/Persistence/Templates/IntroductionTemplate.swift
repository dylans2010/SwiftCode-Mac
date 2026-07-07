import Foundation

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
