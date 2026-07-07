import SwiftUI

struct InfoProjView: View {
    let project: Project
    @State private var manifest: ProjectManifest?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading manifest...")
            } else if let manifest = manifest {
                Form {
                    Section("Project Identity") {
                        LabeledContent("Name", value: manifest.identity.name)
                        LabeledContent("ID", value: manifest.identity.id.uuidString)
                        LabeledContent("Slug", value: manifest.identity.slug)
                        LabeledContent("Created", value: manifest.identity.createdAt, format: .dateTime)
                        LabeledContent("Updated", value: manifest.identity.updatedAt, format: .dateTime)
                        if let lastOpened = manifest.identity.lastOpenedAt {
                            LabeledContent("Last Opened", value: lastOpened, format: .dateTime)
                        }
                    }

                    Section("Application") {
                        LabeledContent("Display Name", value: manifest.bundle.displayName)
                        LabeledContent("Bundle ID", value: manifest.bundle.bundleIdentifier)
                        LabeledContent("Version", value: manifest.bundle.bundleShortVersion)
                        LabeledContent("Build", value: manifest.bundle.bundleVersion)
                    }

                    Section("Platform & Build") {
                        LabeledContent("Platform", value: manifest.platform.targetPlatform)
                        LabeledContent("Deployment Target", value: manifest.platform.deploymentTarget)
                        LabeledContent("Default Config", value: manifest.build.defaultConfiguration)
                    }

                    Section("Statistics") {
                        LabeledContent("File Count", value: "\(manifest.statistics.fileCount)")
                        LabeledContent("Directory Count", value: "\(manifest.statistics.directoryCount)")
                        LabeledContent("Total Size", value: ByteCountFormatter.string(fromByteCount: manifest.statistics.totalSizeInBytes, countStyle: .file))
                    }

                    Section("Security & Integrity") {
                        LabeledContent("Hash Algorithm", value: manifest.security.hashAlgorithm)
                        LabeledContent("Validation Status", value: manifest.validation.validationStatus)
                        if let lastValidation = manifest.validation.lastValidationDate {
                            LabeledContent("Last Validated", value: lastValidation, format: .dateTime)
                        }
                    }

                    Section("Internal Metadata") {
                        LabeledContent("Creator", value: manifest.internalData.creatorTool)
                        LabeledContent("Creator Version", value: manifest.internalData.creatorVersion)
                        LabeledContent("Schema Version", value: "\(manifest.versioning.schemaVersion)")
                    }

                    if !manifest.identity.tags.isEmpty {
                        Section("Tags") {
                            Text(manifest.identity.tags.joined(separator: ", "))
                        }
                    }

                    Section("Description") {
                        Text(manifest.identity.description ?? "No description provided.")
                            .foregroundStyle(manifest.identity.description == nil ? .secondary : .primary)
                    }
                }
                .formStyle(.grouped)
            } else {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error ?? "Failed to load project manifest.")
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .navigationTitle("Project Info")
        .task {
            await loadManifest()
        }
    }

    private func loadManifest() async {
        do {
            // In a real scenario, we'd get the URL from project.directoryURL
            // For now, we'll try to generate a temporary one or use the coordinator
            let packageURL = await project.directoryURL
            if ProjectFileManager.shared.exists(at: packageURL.appendingPathComponent("manifest.json")) {
                self.manifest = try ProjectCoordinator.shared.getManifest(for: packageURL)
            } else {
                // Fallback: create a manifest from project model if it doesn't exist
                self.manifest = ManifestProjManager.shared.createInitialManifest(for: project)
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
