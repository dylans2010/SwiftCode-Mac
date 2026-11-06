// Ported from SwiftCode-Legacy `SwiftCode/Views/Developer/Virtualization/UI/EnvironmentProfilesView.swift` (Dylan's own code; direct port authorised under MIT).
// Audit A: MISSING at bc28f653. Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
//
// Cleanup C24 (2026-11-06): the hardcoded `packageDashboardData` table is deleted — it
// asserted per-profile package versions, install dates and "Update Available" flags
// (e.g. Vapor: Swift Compiler 6.0-release, Git 2.43.0, PostgreSQL Client 16.1, all
// "installed" 2026-01-10…) that were never measured. Real source: query the VM guest
// for installed packages (guest agent / `dpkg -l` / `apk info` over the VM channel).
// No such channel exists in this codebase yet (no SSH/guest-agent command path for
// these VMs), so the dashboard honestly shows version/install date/status as
// unknown and derives its rows only from the selected profile's own
// `installedPackages` list (user-editable profile data). Do not re-seed versions
// or dates here until a real guest query lands.
import SwiftUI
import SwiftCodeUI

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

    // Package Dashboard (C24): rows are derived from the selected profile's own
    // `installedPackages` list. Version, install date and status are honestly
    // unknown — the guest has not been queried (no guest-agent channel exists
    // yet to run `dpkg -l` / `apk info` inside the VM).
    public struct VMPackage: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let version: String
        public let installDate: String
        public let status: String // "Unknown" until the guest is queried
    }

    private func packageDashboardRows(for profile: EnvironmentProfile) -> [VMPackage] {
        profile.installedPackages.map { pkg in
            VMPackage(id: pkg, name: pkg, version: "—", installDate: "—", status: "Unknown")
        }
    }

    public init() {}

    private var activeProfile: EnvironmentProfile? {
        profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Service Profiles & Recipes")
                        .font(.system(size: 24, weight: .bold))
                    Text("Attach repositories to sandbox environments, map custom environment variables, export setup recipes, and review active package lists.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Main split panes
                HStack(alignment: .top, spacing: 16) {
                    // Profile Management Card (Left Column)
                    GroupBox(label:
                        Label("Active Service Recipe", systemImage: "doc.text.image.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Selected Profile:")
                                    .fontWeight(.medium)
                                Spacer()
                                Picker("", selection: $selectedProfileID) {
                                    ForEach(profiles) { prof in
                                        Text("\(prof.name) (\(prof.targetOS))").tag(Optional(prof.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 220)
                            }

                            if let prof = activeProfile {
                                Divider()

                                // Env variables list
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Environment Variables:")
                                        .fontWeight(.bold)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if prof.environmentVariables.isEmpty {
                                        Text("No variables configured.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        VStack(alignment: .leading, spacing: 4) {
                                            ForEach(Array(prof.environmentVariables.keys), id: \.self) { key in
                                                HStack {
                                                    Text(key)
                                                        .font(.system(.caption, design: .monospaced))
                                                        .foregroundStyle(.secondary)
                                                    Text("=")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                    Text(prof.environmentVariables[key] ?? "")
                                                        .font(.system(.caption2, design: .monospaced))
                                                        .fontWeight(.semibold)
                                                }
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 4)
                                                .background(Color.primary.opacity(0.03))
                                                .cornerRadius(4)
                                            }
                                        }
                                    }
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Required System Packages:")
                                        .fontWeight(.bold)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(prof.installedPackages.joined(separator: ", "))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Auto-run Startup Commands:")
                                        .fontWeight(.bold)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    ForEach(prof.startupCommands, id: \.self) { cmd in
                                        Text("$ \(cmd)")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.blue)
                                            .padding(4)
                                            .background(Color.blue.opacity(0.06))
                                            .cornerRadius(4)
                                    }
                                }

                                Divider()

                                Button {
                                    exportRecipe(prof)
                                } label: {
                                    Label("Export Recipe Manifest JSON", systemImage: "square.and.arrow.up.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                    .frame(maxWidth: .infinity)

                    // Packages Inventory dashboard (Right Column)
                    GroupBox(label:
                        Label("Sandbox Package Inventory", systemImage: "shippingbox.fill")
                            .font(.headline)
                            .foregroundStyle(.blue)
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Packages this profile requires. Versions, install dates and update status are unknown until the guest can be queried — no guest-agent channel exists yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Divider()

                            if let prof = activeProfile {
                                let pkgs = packageDashboardRows(for: prof)
                                if pkgs.isEmpty {
                                    Text("No packages listed for this profile.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 16)
                                } else {
                                    VStack(spacing: 0) {
                                        ForEach(pkgs) { pkg in
                                            HStack {
                                                Image(systemName: "questionmark.circle.fill")
                                                    .foregroundStyle(.secondary)
                                                    .font(.headline)
                                                    .frame(width: 24)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(pkg.name)
                                                        .font(.subheadline)
                                                        .fontWeight(.bold)
                                                    Text("Version unknown • Status: Unknown — guest not queried")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()

                                                Text(pkg.version)
                                                    .font(.system(.caption, design: .monospaced))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(Color.primary.opacity(0.05))
                                                    .cornerRadius(4)
                                            }
                                            .padding(.vertical, 8)

                                            if pkg.id != pkgs.last?.id {
                                                Divider()
                                            }
                                        }
                                    }
                                }
                            } else {
                                Text("No pre-built package manifests indexed for this custom configuration.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 16)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                    .frame(maxWidth: .infinity)
                }

                // Add Profile Form
                GroupBox(label: Text("Create Custom Service Profile Recipe").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            TextField("Recipe Title Name (e.g. FastAPI Backplane)", text: $newProfileName)
                                .textFieldStyle(.roundedBorder)

                            Picker("", selection: $newProfileOS) {
                                Text("Ubuntu").tag("Ubuntu")
                                Text("Debian").tag("Debian")
                                Text("Fedora").tag("Fedora")
                                Text("Alpine").tag("Alpine")
                            }
                            .frame(width: 140)

                            Button("Create Recipe Profile") {
                                createProfile()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newProfileName.isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingRecipeExport) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "curlybraces")
                        .font(.title)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export Provisioning Recipe")
                            .font(.headline)
                        Text("Manifest ready for git synchronization and deployment.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Close") {
                        showingRecipeExport = false
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                TextEditor(text: .constant(recipeExportJSON))
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 250)
                    .border(Color.secondary.opacity(0.2))

                HStack {
                    Button("Copy Manifest to Clipboard") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(recipeExportJSON, forType: .string)
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
            }
            .padding(20)
            .frame(width: 500, height: 420)
        }
    }

    private func createProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let prof = EnvironmentProfile(
            name: name,
            targetOS: newProfileOS,
            environmentVariables: ["ENV": "development", "PORT": "8000"],
            startupCommands: ["echo 'Deploying python stack...'"],
            installedPackages: ["git", "curl", "python3"]
        )
        profiles.append(prof)
        selectedProfileID = prof.id
        newProfileName = ""
        stateStore.addLog("Created service profile recipe '\(name)'.", type: .success)
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
