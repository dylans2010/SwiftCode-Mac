import SwiftUI

enum DependencyRequirementType: String, CaseIterable, Identifiable, Codable {
    case from = "from"
    case branch = "branch"
    case revision = "revision"
    case exact = "exact"

    var id: String { rawValue }
}

struct ParsedDependency: Identifiable, Codable {
    var id = UUID()
    var url: String
    var requirementType: DependencyRequirementType
    var value: String

    var name: String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let urlObj = URL(string: trimmed) {
            let lastComponent = urlObj.deletingPathExtension().lastPathComponent
            return lastComponent.isEmpty ? trimmed : lastComponent
        }
        return trimmed
    }
}

struct DependencyManagerView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var dependencies: [ParsedDependency] = []
    @State private var showAddSheet = false
    @State private var newURL = ""
    @State private var newRequirementType: DependencyRequirementType = .from
    @State private var newValue = "1.0.0"
    @State private var editingDependency: ParsedDependency?
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Status Info Card
                    GroupBox {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Package.swift Source of Truth", systemImage: "doc.text.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Text("This interface edits Package.swift directly. All modifications are synchronized immediately.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            Button {
                                loadDependencies()
                            } label: {
                                Label("Reload", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(12)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    if dependencies.isEmpty {
                        GroupBox {
                            VStack(spacing: 16) {
                                Image(systemName: "shippingbox")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.secondary.opacity(0.6))
                                Text("No Dependencies Yet")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Add Swift Package dependencies to this project.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Button("Add Dependency") {
                                    resetAddForm()
                                    showAddSheet = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .controlSize(.large)
                            }
                            .padding(32)
                            .frame(maxWidth: .infinity)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    } else {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Swift Package Dependencies", systemImage: "shippingbox.fill")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Spacer()
                                    Text("\(dependencies.count) Packages")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.secondary)
                                }

                                Divider()

                                VStack(spacing: 12) {
                                    ForEach(dependencies) { dep in
                                        HStack(alignment: .center, spacing: 16) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(Color.orange.opacity(0.12))
                                                    .frame(width: 44, height: 44)
                                                Image(systemName: "shippingbox")
                                                    .font(.title3)
                                                    .foregroundColor(.orange)
                                            }

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(dep.name)
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.primary)
                                                Text(dep.url)
                                                    .font(.caption2)
                                                    .foregroundStyle(.blue)
                                                    .lineLimit(1)
                                                HStack {
                                                    Text("\(dep.requirementType.rawValue): \(dep.value)")
                                                        .font(.caption2.bold())
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                                        .foregroundStyle(.orange)
                                                }
                                            }

                                            Spacer()

                                            HStack(spacing: 8) {
                                                Button {
                                                    beginEdit(dep)
                                                } label: {
                                                    Image(systemName: "pencil")
                                                }
                                                .buttonStyle(.bordered)
                                                .help("Edit Dependency")

                                                Button(role: .destructive) {
                                                    removeDependency(dep)
                                                } label: {
                                                    Image(systemName: "trash")
                                                }
                                                .buttonStyle(.bordered)
                                                .help("Delete Dependency")
                                            }
                                        }
                                        .padding(10)
                                        .background(Color.secondary.opacity(0.04))
                                        .cornerRadius(8)
                                    }
                                }

                                Divider()

                                // The Add Dependency action button inside the card itself - ALWAYS accessible!
                                Button {
                                    resetAddForm()
                                    showAddSheet = true
                                } label: {
                                    Label("Add New Package Dependency", systemImage: "plus.circle.fill")
                                        .fontWeight(.semibold)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .padding(.top, 4)
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Dependencies")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                // Persistent toolbar plus button - ALWAYS available!
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        resetAddForm()
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                addDependencySheet
            }
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK") {}
            } message: { msg in Text(msg) }
            .onAppear { loadDependencies() }
        }
    }

    // MARK: - Add/Edit Dependency Sheet

    private var addDependencySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Package Specifications", systemImage: "puzzlepiece.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Repository URL")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("e.g. https://github.com/Alamofire/Alamofire.git", text: $newURL)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Requirement Specification")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)

                                Picker("Requirement Type", selection: $newRequirementType) {
                                    ForEach(DependencyRequirementType.allCases) { type in
                                        Text(type.rawValue).tag(type)
                                    }
                                }
                                .pickerStyle(.segmented)

                                TextField(placeholderText, text: $newValue)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Live Code Preview matching edits
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Package.swift Output Syntax", systemImage: "doc.text.fill")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            Text(previewEntry)
                                .font(.caption.monospaced())
                                .foregroundStyle(.green)
                                .textSelection(.enabled)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(8)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle(editingDependency != nil ? "Edit Dependency" : "Add Dependency")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingDependency != nil ? "Save" : "Add") {
                        saveDependency()
                    }
                    .disabled(newURL.isEmpty || newValue.isEmpty)
                }
            }
        }
        .frame(width: 550, height: 500)
    }

    private var placeholderText: String {
        switch newRequirementType {
        case .from: return "Version number (e.g. 5.8.0)"
        case .branch: return "Branch name (e.g. main)"
        case .revision: return "Revision SHA (e.g. 0ea8b21)"
        case .exact: return "Exact version (e.g. 1.5.3)"
        }
    }

    private var previewEntry: String {
        ".package(url: \"\(newURL)\", \(newRequirementType.rawValue): \"\(newValue)\")"
    }

    // MARK: - Actions

    private func loadDependencies() {
        guard let project = sessionStore.activeProject else { return }
        let packageURL = project.directoryURL.appendingPathComponent("Package.swift")
        guard let content = try? String(contentsOf: packageURL, encoding: .utf8) else { return }

        // Robust parsing of Package.swift dependencies block
        let pattern = #"\.package\(url:\s*"([^"]+)",\s*(from|branch|revision|exact):\s*"([^"]+)"\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        var parsedList: [ParsedDependency] = []
        for match in matches {
            let url = nsContent.substring(with: match.range(at: 1))
            let reqTypeRaw = nsContent.substring(with: match.range(at: 2))
            let val = nsContent.substring(with: match.range(at: 3))

            let reqType = DependencyRequirementType(rawValue: reqTypeRaw) ?? .from
            parsedList.append(ParsedDependency(url: url, requirementType: reqType, value: val))
        }

        self.dependencies = parsedList
    }

    private func saveDependency() {
        let urlStr = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let valStr = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editing = editingDependency, let idx = dependencies.firstIndex(where: { $0.id == editing.id }) {
            dependencies[idx].url = urlStr
            dependencies[idx].requirementType = newRequirementType
            dependencies[idx].value = valStr
        } else {
            let dep = ParsedDependency(url: urlStr, requirementType: newRequirementType, value: valStr)
            dependencies.append(dep)
        }

        updatePackageSwift()
        showAddSheet = false
        editingDependency = nil
    }

    private func removeDependency(_ dep: ParsedDependency) {
        dependencies.removeAll { $0.id == dep.id }
        updatePackageSwift()
    }

    private func beginEdit(_ dep: ParsedDependency) {
        editingDependency = dep
        newURL = dep.url
        newRequirementType = dep.requirementType
        newValue = dep.value
        showAddSheet = true
    }

    private func resetAddForm() {
        editingDependency = nil
        newURL = ""
        newRequirementType = .from
        newValue = "1.0.0"
    }

    private func updatePackageSwift() {
        guard let project = sessionStore.activeProject else { return }
        let packageURL = project.directoryURL.appendingPathComponent("Package.swift")

        let depsString = dependencies.map { dep in
            "        .package(url: \"\(dep.url)\", \(dep.requirementType.rawValue): \"\(dep.value)\")"
        }.joined(separator: ",\n")

        let packageContent = """
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "\(project.name)",
    platforms: [.iOS(.v17)],
    dependencies: [
\(depsString)
    ],
    targets: [
        .executableTarget(
            name: "\(project.name)",
            path: "Sources"
        )
    ]
)
"""
        do {
            try packageContent.write(to: packageURL, atomically: true, encoding: .utf8)
            sessionStore.refreshFileTree(for: project)
        } catch {
            errorMessage = "Failed to write Package.swift: \(error.localizedDescription)"
            showError = true
        }
    }
}
