import SwiftUI

struct DependencyManagerView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
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
            ScrollView {
                VStack(spacing: 24) {
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
                        // Card 1: Pinned Dependencies (Modern Card Styling matching DeploymentsView)
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
                                                    Text("v\(dep.version)")
                                                        .font(.caption2.bold())
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                                        .foregroundStyle(.orange)
                                                    Text(dep.source.rawValue.uppercased())
                                                        .font(.system(size: 8, weight: .bold))
                                                        .foregroundStyle(.secondary)
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
            ScrollView {
                VStack(spacing: 24) {
                    // Card 1: Dependency Fields
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Package Specifications", systemImage: "puzzlepiece.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Package Name")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("e.g. Alamofire", text: $newName)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Repository URL")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("e.g. https://github.com/Alamofire/Alamofire.git", text: $newURL)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Version Requirement")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("e.g. 5.8.0", text: $newVersion)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 2: Source Type
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Package Registry Source", systemImage: "network")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                Spacer()
                            }

                            Picker("Source", selection: $newSource) {
                                ForEach(PackageDependency.DependencySource.allCases, id: \.self) { source in
                                    Text(source.rawValue).tag(source)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 3: Code Preview
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Package.swift Declaration", systemImage: "doc.text.fill")
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
                    .disabled(newName.isEmpty || newURL.isEmpty)
                }
            }
        }
        .frame(width: 550, height: 500)
    }

    private var previewEntry: String {
        ".package(url: \"\(newURL)\", from: \"\(newVersion)\")"
    }

    // MARK: - Actions

    private func loadDependencies() {
        guard let project = sessionStore.activeProject else { return }
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
        guard let project = sessionStore.activeProject else { return }
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
        sessionStore.refreshFileTree(for: project)
    }
}
