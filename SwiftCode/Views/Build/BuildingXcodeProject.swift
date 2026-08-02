import SwiftUI

public struct BuildingXcodeProject: View {
    @Environment(\.dismiss) private var dismiss

    // Shared API reference
    private let api = XcodeBuildAPI.shared

    // State management
    @State private var stage: String = "Initializing..."
    @State private var isChecking = true
    @State private var needsGeneration = false
    @State private var logs: [String] = []

    // Form variables for XcodeProjectDetails
    @State private var projectName = "MyProject"
    @State private var scheme = "MyProject"
    @State private var bundleIdentifier = "com.example.myproject"

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            if isChecking {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)

                    Text(stage)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if needsGeneration {
                XcodeProjectDetails(
                    projectName: $projectName,
                    scheme: $scheme,
                    bundleIdentifier: $bundleIdentifier,
                    onGenerate: {
                        startGeneration()
                    },
                    onCancel: {
                        dismiss()
                    }
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)

                    Text("Ready!")
                        .font(.title2.bold())

                    Text(stage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(32)
        .frame(width: 450, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            runPrecheck()
        }
    }

    private func runPrecheck() {
        stage = "Searching for existing Xcode projects..."
        isChecking = true
        needsGeneration = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            stage = "Validating build environment..."

            Task {
                let validation = await api.validateBuildEnvironment()

                if let project = api.discoverActiveProject() {
                    stage = "Located project: \(project.name)"
                    isChecking = false
                    // Auto-close on success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        dismiss()
                    }
                } else {
                    stage = "No supported project found. Ready to generate."
                    isChecking = false
                    needsGeneration = true
                }
            }
        }
    }

    private func startGeneration() {
        isChecking = true
        stage = "Generating Xcode project '\(projectName)'..."

        Task {
            // Determine target destination directory. Use standard projectsRoot or current project folder.
            let targetURL = ProjectSessionStore.shared.activeProject?.directoryURL ?? CodingManager.shared.projectsRoot.appendingPathComponent(projectName)

            let result = await api.generateProject(
                projectName: projectName,
                scheme: scheme,
                bundleIdentifier: bundleIdentifier,
                targetURL: targetURL
            )

            if result.success, let projPath = result.generatedProjectPath {
                stage = "Project successfully generated!"
                isChecking = false
                needsGeneration = false

                // Refresh folder tree so that it updates instantly in the editor
                if let activeProj = ProjectSessionStore.shared.activeProject {
                    ProjectSessionStore.shared.refreshFileTree(for: activeProj)
                }

                // Close window after completion
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    dismiss()
                }
            } else {
                stage = "Generation failed: \(result.errorDescription ?? "Unknown error")"
                isChecking = false
            }
        }
    }
}

// MARK: - XcodeProjectDetails View

public struct XcodeProjectDetails: View {
    @Binding var projectName: String
    @Binding var scheme: String
    @Binding var bundleIdentifier: String

    var onGenerate: () -> Void
    var onCancel: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "hammer.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("New Xcode Project Configuration")
                    .font(.title3.bold())
            }
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 14) {
                // User input configuration fields
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project Name")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("MyProject", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: projectName) { _, newVal in
                            // Auto align scheme with project name for convenience
                            scheme = newVal
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Scheme")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("MyProject", text: $scheme)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Bundle Identifier")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("com.example.myproject", text: $bundleIdentifier)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()
                    .padding(.vertical, 4)

                // API Controlled properties (readonly indicators)
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Controlled Infrastructure")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Group {
                        apiMetadataRow(label: "Project Path", val: "Managed Sandbox Workspace")
                        apiMetadataRow(label: "Workspace Mode", val: "Automatic Resolution")
                        apiMetadataRow(label: "Build Directory", val: "Standard Out (API Managed)")
                        apiMetadataRow(label: "DerivedData", val: "Isolated Sandbox DerivedData")
                    }
                    .font(.system(size: 11))
                }
            }

            Spacer()

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Spacer()

                Button("Generate Project", action: onGenerate)
                    .buttonStyle(.borderedProminent)
                    .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func apiMetadataRow(label: String, val: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(val)
                .foregroundStyle(.secondary)
        }
    }
}
