import SwiftUI

public struct EnvironmentProfilesView: View {
    @State private var stateStore = VirtualizationStateStore.shared
    @State private var profiles: [EnvironmentProfile] = [
        EnvironmentProfile(
            name: "Vapor Backend Stack",
            targetOS: "Ubuntu",
            environmentVariables: ["PORT": "8080", "DB_URL": "postgresql://localhost:5432", "ENV": "development"],
            startupCommands: ["swift package resolve", "swift run App"],
            installedPackages: ["swift", "git", "clang", "postgresql"]
        ),
        EnvironmentProfile(
            name: "React & Node Gateway",
            targetOS: "Ubuntu",
            environmentVariables: ["PORT": "3000", "API_URL": "http://localhost:8080"],
            startupCommands: ["npm install", "npm run dev"],
            installedPackages: ["node", "npm", "git"]
        ),
        EnvironmentProfile(
            name: "Redis Cache Tunnel",
            targetOS: "Alpine",
            environmentVariables: ["REDIS_PORT": "6379"],
            startupCommands: ["redis-server --protected-mode no"],
            installedPackages: ["redis", "git"]
        )
    ]

    @State private var selectedProfileID: UUID? = nil
    @State private var newProfileName: String = ""
    @State private var newProfileOS: String = "Ubuntu"
    @State private var showingRecipeExport = false
    @State private var recipeExportJSON = ""

    // Package Dashboard mock metadata linked to VM configurations
    public struct VMPackage: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let version: String
        public let installDate: String
        public let status: String // "Installed", "Update Available"
    }

    private let packageDashboardData: [String: [VMPackage]] = [
        "Vapor Backend Stack": [
            VMPackage(id: "pkg1", name: "Swift Compiler", version: "6.0-release", installDate: "2026-01-10", status: "Installed"),
            VMPackage(id: "pkg2", name: "Git", version: "2.43.0", installDate: "2026-01-10", status: "Installed"),
            VMPackage(id: "pkg3", name: "PostgreSQL Client", version: "16.1", installDate: "2026-01-12", status: "Update Available"),
            VMPackage(id: "pkg4", name: "Clang/LLVM Compiler", version: "17.0.6", installDate: "2026-01-10", status: "Installed")
        ],
        "React & Node Gateway": [
            VMPackage(id: "pkg1", name: "Node.js Platform", version: "20.11.0", installDate: "2026-02-01", status: "Installed"),
            VMPackage(id: "pkg2", name: "NPM Package Manager", version: "10.2.4", installDate: "2026-02-01", status: "Update Available"),
            VMPackage(id: "pkg3", name: "Git Source Code Control", version: "2.43.0", installDate: "2026-01-15", status: "Installed")
        ],
        "Redis Cache Tunnel": [
            VMPackage(id: "pkg1", name: "Redis Key-Value Cache", version: "7.2.4", installDate: "2026-02-04", status: "Installed"),
            VMPackage(id: "pkg2", name: "Git Source Code Control", version: "2.40.1", installDate: "2026-02-04", status: "Installed")
        ]
    ]

    public init() {}

    private var activeProfile: EnvironmentProfile? {
        profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Development Profiles & Packages")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Attach projects to VM configurations, manage environment variables, export recipes, and review installed packages.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Split sections for profiles and packages
                HStack(alignment: .top, spacing: 16) {
                    // Profile Management Card (Left)
                    GroupBox(label: Text("Workspace Active Profile").font(.headline)) {
                        VStack(alignment: .leading, spacing: 12) {
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
                                        .font(.caption)
                                    if prof.environmentVariables.isEmpty {
                                        Text("None configured.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(Array(prof.environmentVariables.keys), id: \.self) { key in
                                            Text("• \(key) = \(prof.environmentVariables[key] ?? "")")
                                                .font(.system(.caption2, design: .monospaced))
                                        }
                                    }
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Container Packages:")
                                        .fontWeight(.bold)
                                        .font(.caption)
                                    Text(prof.installedPackages.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Auto Startup Commands:")
                                        .fontWeight(.bold)
                                        .font(.caption)
                                    ForEach(prof.startupCommands, id: \.self) { cmd in
                                        Text("$ \(cmd)")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.blue)
                                    }
                                }

                                Divider()

                                // Recipe Export Action
                                Button {
                                    exportRecipe(prof)
                                } label: {
                                    Label("Export Recipe JSON", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                    .frame(maxWidth: .infinity)

                    // Packages Dashboard Card (Right)
                    GroupBox(label: Text("VM Guest Package Dashboard").font(.headline)) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Package inventory active inside this virtual development stack.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Divider()

                            if let prof = activeProfile,
                               let pkgs = packageDashboardData[prof.name] {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(pkgs) { pkg in
                                        HStack {
                                            Image(systemName: "shippingbox.fill")
                                                .foregroundStyle(pkg.status == "Update Available" ? .orange : .blue)
                                                .frame(width: 20)

                                            VStack(alignment: .leading) {
                                                Text(pkg.name)
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                Text("Installed: \(pkg.installDate) • Status: \(pkg.status)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()

                                            Text(pkg.version)
                                                .font(.system(.caption, design: .monospaced))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.primary.opacity(0.06))
                                                .cornerRadius(4)
                                        }
                                        Divider()
                                    }
                                }
                            } else {
                                Text("No pre-packaged templates registered for this custom configuration.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 10)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                    .frame(maxWidth: .infinity)
                }

                // Add Profile Form
                GroupBox(label: Text("Create Development Profile & Recipe").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            TextField("Recipe Name (e.g. Django Server Stack)", text: $newProfileName)
                                .textFieldStyle(.roundedBorder)

                            Picker("", selection: $newProfileOS) {
                                Text("Ubuntu").tag("Ubuntu")
                                Text("Debian").tag("Debian")
                                Text("Fedora").tag("Fedora")
                                Text("Alpine").tag("Alpine")
                            }
                            .frame(width: 140)

                            Button("Create Recipe") {
                                createProfile()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding()
        }
        .sheet(isPresented: $showingRecipeExport) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Export Development Recipe")
                    .font(.headline)
                Text("This recipe represents standard provisioning code ready for containers, Docker or local VMs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: .constant(recipeExportJSON))
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 250)
                    .border(Color.secondary.opacity(0.3))

                HStack {
                    Button("Copy Recipe") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(recipeExportJSON, forType: .string)
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button("Close") {
                        showingRecipeExport = false
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .frame(width: 480, height: 400)
        }
    }

    private func createProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let prof = EnvironmentProfile(
            name: name,
            targetOS: newProfileOS,
            environmentVariables: ["ENV": "production"],
            startupCommands: ["echo 'Running server recipe...'"],
            installedPackages: ["git", "curl"]
        )
        profiles.append(prof)
        selectedProfileID = prof.id
        newProfileName = ""
        stateStore.addLog("Created development recipe '\(name)'.", type: .success)
    }

    private func exportRecipe(_ prof: EnvironmentProfile) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(prof) {
            recipeExportJSON = String(data: data, encoding: .utf8) ?? ""
            showingRecipeExport = true
        }
    }
}
