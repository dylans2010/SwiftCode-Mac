import SwiftUI

struct DependencyManagerView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss

    @State private var dependencies: [PackageDependency] = []
    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var newURL = ""
    @State private var newVersion = "1.0.0"
    @State private var newSource: PackageDependency.DependencySource = .github
    @State private var editingDependency: PackageDependency?
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if dependencies.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text("No Dependencies Yet")
                            .foregroundStyle(.secondary)
                        Text("Add Swift Package dependencies to this project.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(dependencies) { dep in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dep.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                Text(dep.url)
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .lineLimit(1)
                                HStack {
                                    Text("v\(dep.version)")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                                        .foregroundStyle(.orange)
                                    Text(dep.source.rawValue)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    removeDependency(dep)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    beginEdit(dep)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
            .navigationTitle("Dependencies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
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

    // MARK: - Add Dependency Sheet

    private var addDependencySheet: some View {
        NavigationStack {
            Form {
                Section("Package Info") {
                    TextField("Package Name", text: $newName)
                        .autocorrectionDisabled()
                    TextField("Repository URL", text: $newURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Version", text: $newVersion)
                        .autocorrectionDisabled()
                }

                Section("Source") {
                    Picker("Source", selection: $newSource) {
                        ForEach(PackageDependency.DependencySource.allCases, id: \.self) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Preview") {
                    Text(previewEntry)
                        .font(.caption.monospaced())
                        .foregroundStyle(.green)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
            .navigationTitle(editingDependency != nil ? "Edit Dependency" : "Add Dependency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingDependency != nil ? "Save" : "Add") {
                        saveDependency()
                    }
                    .disabled(newName.isEmpty || newURL.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var previewEntry: String {
        ".package(url: \"\(newURL)\", from: \"\(newVersion)\")"
    }

    // MARK: - Actions

    private func loadDependencies() {
        guard let project = projectManager.activeProject else { return }
        let packageURL = project.directoryURL.appendingPathComponent("Package.swift")
        // Parse simple dependencies from Package.swift if it exists
        guard let content = try? String(contentsOf: packageURL, encoding: .utf8) else { return }
        // Simple regex parsing for .package entries
        let pattern = #"\.package\(url:\s*"([^"]+)",\s*from:\s*"([^"]+)"\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
        dependencies = matches.map { match in
            let url = nsContent.substring(with: match.range(at: 1))
            let version = nsContent.substring(with: match.range(at: 2))
            let name = URL(string: url)?.deletingPathExtension().lastPathComponent ?? url
            return PackageDependency(name: name, url: url, version: version, source: .github)
        }
    }

    private func saveDependency() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = newVersion.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editing = editingDependency, let idx = dependencies.firstIndex(where: { $0.id == editing.id }) {
            dependencies[idx].name = name
            dependencies[idx].url = url
            dependencies[idx].version = version
            dependencies[idx].source = newSource
        } else {
            let dep = PackageDependency(name: name, url: url, version: version, source: newSource)
            dependencies.append(dep)
        }

        updatePackageSwift()
        showAddSheet = false
        editingDependency = nil
    }

    private func removeDependency(_ dep: PackageDependency) {
        dependencies.removeAll { $0.id == dep.id }
        updatePackageSwift()
    }

    private func beginEdit(_ dep: PackageDependency) {
        editingDependency = dep
        newName = dep.name
        newURL = dep.url
        newVersion = dep.version
        newSource = dep.source
        showAddSheet = true
    }

    private func resetAddForm() {
        editingDependency = nil
        newName = ""
        newURL = ""
        newVersion = "1.0.0"
        newSource = .github
    }

    private func updatePackageSwift() {
        guard let project = projectManager.activeProject else { return }
        let packageURL = project.directoryURL.appendingPathComponent("Package.swift")
        let depsString = dependencies.map { "        \($0.packageSwiftEntry)" }.joined(separator: ",\n")
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
        try? packageContent.write(to: packageURL, atomically: true, encoding: .utf8)
        projectManager.refreshFileTree(for: project)
    }
}
