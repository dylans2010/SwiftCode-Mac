import SwiftUI

public struct EnvironmentProfilesView: View {
    @State private var stateStore = VirtualizationStateStore.shared
    @State private var profiles: [EnvironmentProfile] = [
        EnvironmentProfile(
            name: "Ubuntu Backend API",
            targetOS: "Ubuntu",
            environmentVariables: ["PORT": "8080", "DB_URL": "postgresql://localhost:5432"],
            startupCommands: ["npm install", "npm run dev"],
            installedPackages: ["node", "npm", "git"]
        ),
        EnvironmentProfile(
            name: "Fedora ML Playground",
            targetOS: "Fedora",
            environmentVariables: ["PYTHONPATH": "/usr/local/bin/python3"],
            startupCommands: ["pip install torch torchvision numpy"],
            installedPackages: ["python3", "pip", "gcc"]
        ),
        EnvironmentProfile(
            name: "Alpine Micro Gateway",
            targetOS: "Alpine",
            environmentVariables: ["ENV": "production"],
            startupCommands: ["apk add nginx", "nginx"],
            installedPackages: ["nginx"]
        )
    ]

    @State private var selectedProfileID: UUID? = nil
    @State private var newProfileName: String = ""
    @State private var newProfileOS: String = "Ubuntu"

    public init() {}

    private var activeProfile: EnvironmentProfile? {
        profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Development Profiles")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Attach projects to VM configurations, manage environment variables, and configure automated container startup scripts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GroupBox(label: Text("Create Profile").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            TextField("Profile Name (e.g. Django API Test)", text: $newProfileName)
                                .textFieldStyle(.roundedBorder)

                            Picker("", selection: $newProfileOS) {
                                Text("Ubuntu").tag("Ubuntu")
                                Text("Debian").tag("Debian")
                                Text("Fedora").tag("Fedora")
                                Text("Alpine").tag("Alpine")
                            }
                            .frame(width: 140)

                            Button("Create Profile") {
                                createProfile()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox(label: Text("Workspace Active Profile Details").font(.headline)) {
                    VStack(alignment: .leading, spacing: 14) {
                        // Profile pickers
                        Picker("Select Profile:", selection: $selectedProfileID) {
                            ForEach(profiles) { prof in
                                Text("\(prof.name) (\(prof.targetOS))").tag(Optional(prof.id))
                            }
                        }
                        .pickerStyle(.menu)

                        if let prof = activeProfile {
                            Divider()
                                .padding(.vertical, 4)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Environment Variables:")
                                    .fontWeight(.bold)
                                if prof.environmentVariables.isEmpty {
                                    Text("None configured.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(Array(prof.environmentVariables.keys), id: \.self) { key in
                                        Text("• \(key) = \(prof.environmentVariables[key] ?? "")")
                                            .font(.system(.subheadline, design: .monospaced))
                                    }
                                }
                            }

                            Divider()
                                .padding(.vertical, 4)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Container Packages:")
                                    .fontWeight(.bold)
                                Text(prof.installedPackages.joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Divider()
                                .padding(.vertical, 4)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Auto Startup Commands:")
                                    .fontWeight(.bold)
                                ForEach(prof.startupCommands, id: \.self) { cmd in
                                    Text("$ \(cmd)")
                                        .font(.system(.subheadline, design: .monospaced))
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding()
        }
    }

    private func createProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let prof = EnvironmentProfile(
            name: name,
            targetOS: newProfileOS,
            environmentVariables: [:],
            startupCommands: ["echo 'Environment started successfully'"],
            installedPackages: ["git"]
        )
        profiles.append(prof)
        selectedProfileID = prof.id
        newProfileName = ""
        stateStore.addLog("Created development profile '\(name)'.", type: .success)
    }
}
