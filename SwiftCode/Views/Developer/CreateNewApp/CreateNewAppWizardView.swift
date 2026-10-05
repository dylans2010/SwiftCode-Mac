import SwiftUI

public enum CreateAppPlatform: String, CaseIterable, Identifiable, Sendable {
    case macOS = "macOS"
    case iOS = "iOS"
    case iPadOS = "iPadOS"
    case watchOS = "watchOS"
    case visionOS = "visionOS"

    public var id: String { rawValue }
    public var icon: String {
        switch self {
        case .macOS: return "macbook"
        case .iOS: return "iphone"
        case .iPadOS: return "ipad"
        case .watchOS: return "applewatch"
        case .visionOS: return "visionpro"
        }
    }
}

public enum CreateAppStyle: String, CaseIterable, Identifiable, Sendable {
    case native = "Native"
    case minimal = "Minimal"
    case productivity = "Productivity"
    case editorial = "Editorial"
    case utility = "Utility"
    case dashboard = "Dashboard"

    public var id: String { rawValue }
}

public enum CreateAppNavigation: String, CaseIterable, Identifiable, Sendable {
    case sidebar = "Sidebar"
    case tabBased = "Tab-based"
    case navigationStack = "Navigation Stack"
    case adaptive = "Adaptive"

    public var id: String { rawValue }
}

public enum CreateAppPersistence: String, CaseIterable, Identifiable, Sendable {
    case automatic = "Automatic"
    case fileBased = "File-based (JSON)"
    case swiftData = "SwiftData"
    case sqlite = "SQLite"
    case userDefaults = "UserDefaults"

    public var id: String { rawValue }
}

public struct CreateAppConfiguration: Sendable {
    public var appName: String = ""
    public var bundleIdentifier: String = ""
    public var version: String = "1.0"
    public var build: String = "1"
    public var platform: CreateAppPlatform = .macOS
    public var projectLocation: String = ""
    public var applicationDescription: String = ""

    // UI Preferences
    public var visualStyle: CreateAppStyle = .native
    public var density: Double = 0.5 // 0.0 Compact <-> 1.0 Spacious
    public var navigation: CreateAppNavigation = .sidebar
    public var useAnimations: Bool = true
    public var prioritizeAccessibility: Bool = true
    public var persistence: CreateAppPersistence = .automatic

    // Advanced Options
    public var swiftVersion: String = "5.9"
    public var architecturePreference: String = "MVVM with Observable Stores"
    public var overwriteExistingMetadata: Bool = false
    public var createTests: Bool = true
    public var runTestsAfterImplementation: Bool = true
    public var buildAfterImplementation: Bool = true
}

public struct CreateNewAppWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var config = CreateAppConfiguration()
    @State private var currentStep: Int = 1

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create New App")
                        .font(.headline)
                    Text("Autonomous Application Generation Workflow")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Step Content Area
            VStack {
                switch currentStep {
                case 1:
                    CreateNewAppIdeaView(config: $config)
                case 2:
                    CreateNewAppMetadataView(config: $config)
                case 3:
                    CreateNewAppUIOptionsView(config: $config)
                case 4:
                    CreateNewAppAdvancedView(config: $config)
                default:
                    CreateNewAppIdeaView(config: $config)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer Navigation
            HStack {
                if currentStep > 1 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                }
                Spacer()
                Text("Step \(currentStep) of 4")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                if currentStep < 4 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(currentStep == 1 && config.applicationDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Generate Application") {
                        startGeneration()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 720, height: 560)
        .onAppear {
            autoDetectActiveProject()
        }
    }

    private func autoDetectActiveProject() {
        if let active = ProjectSessionStore.shared.activeProject {
            if config.appName.isEmpty { config.appName = active.name }
            if config.projectLocation.isEmpty { config.projectLocation = active.directoryURL.path }
            if config.bundleIdentifier.isEmpty {
                let safeName = active.name.replacingOccurrences(of: " ", with: "").lowercased()
                config.bundleIdentifier = "com.swiftcode.\(safeName)"
            }
        }
    }

    private func startGeneration() {
        if config.appName.isEmpty {
            config.appName = "NewApp"
        }
        if config.bundleIdentifier.isEmpty {
            let safeName = config.appName.replacingOccurrences(of: " ", with: "").lowercased()
            config.bundleIdentifier = "com.swiftcode.\(safeName)"
        }
        if config.projectLocation.isEmpty {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "/tmp")
            config.projectLocation = docs.appendingPathComponent(config.appName).path
        }

        dismiss()

        let appPrompt = """
        Use the create_new_app tool to scaffold and build a new \(config.platform.rawValue) application:
        - App Name: \(config.appName)
        - Bundle ID: \(config.bundleIdentifier)
        - Version: \(config.version) (\(config.build))
        - Platform: \(config.platform.rawValue)
        - Project Path: \(config.projectLocation)
        - Description: \(config.applicationDescription)
        - Architecture: \(config.architecturePreference)
        - UI Style: \(config.visualStyle.rawValue)
        - Navigation: \(config.navigation.rawValue)
        - Persistence: \(config.persistence.rawValue)
        - Overwrite Existing Metadata: \(config.overwriteExistingMetadata)

        Please scaffold the application project structure at \(config.projectLocation), create initial Swift source files and project configurations, and generate an app_summary.md document.
        """

        Task {
            await AssistManager.shared.sendMessage(appPrompt)
        }
    }
}
