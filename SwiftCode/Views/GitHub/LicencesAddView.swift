import SwiftUI

struct LicencesAddView: View {
    let project: Project

    enum SortMode: String, CaseIterable, Identifiable {
        case nameAZ = "Name A-Z"
        case nameZA = "Name Z-A"
        case category = "Category"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectSessionStore.self) private var sessionStore

    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var sortMode: SortMode = .nameAZ
    @State private var previewLicense: LicenseTemplate?
    @State private var isWriting = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var categories: [String] {
        ["All"] + Array(Set(LicenseCatalog.all.map(\.category))).sorted()
    }

    private var filteredLicenses: [LicenseTemplate] {
        var values = LicenseCatalog.all

        if selectedCategory != "All" {
            values = values.filter { $0.category == selectedCategory }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            values = values.filter {
                $0.name.lowercased().contains(query) ||
                $0.summary.lowercased().contains(query) ||
                $0.category.lowercased().contains(query)
            }
        }

        switch sortMode {
        case .nameAZ: values.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .nameZA: values.sort { $0.name.localizedCompare($1.name) == .orderedDescending }
        case .category: values.sort { ($0.category, $0.name) < ($1.category, $1.name) }
        }
        return values
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar List of Licenses
            VStack(spacing: 0) {
                // Filters Header Card
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search licenses...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )

                    HStack(spacing: 8) {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categories, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)

                        Spacer()

                        Picker("Sort", selection: $sortMode) {
                            ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)

                Divider()

                if filteredLicenses.isEmpty {
                    ContentUnavailableView(
                        "No Licenses Found",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Try adjusting your search filters.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List(filteredLicenses, selection: $previewLicense) { license in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(license.name)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Spacer()
                                Text(license.category)
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.blue)
                            }

                            Text(license.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 6)
                        .tag(license)
                    }
                    .listStyle(.sidebar)
                }
            }
            .navigationTitle("Add License")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: { dismiss() }) {
                        Text("Close")
                            .fontWeight(.semibold)
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        } detail: {
            // Detailed License Preview & Action Screen
            if let license = previewLicense {
                ScrollView {
                    VStack(spacing: 24) {
                        // Title Header Panel
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(license.name)
                                            .font(.title2.bold())
                                        HStack(spacing: 8) {
                                            Text(license.category)
                                                .font(.subheadline.bold())
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Color.blue.opacity(0.15), in: Capsule())
                                                .foregroundStyle(.blue)

                                            Text("Offline Available")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // License Meta summary card
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label("License Summary", systemImage: "text.alignleft")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Spacer()
                                }
                                Text(license.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(4)
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // Actions panel card
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label("Action", systemImage: "play.circle.fill")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                    Spacer()
                                }

                                Button {
                                    Task { await addLicense(license) }
                                } label: {
                                    HStack {
                                        if isWriting {
                                            ProgressView()
                                                .controlSize(.small)
                                                .padding(.trailing, 8)
                                        } else {
                                            Image(systemName: "plus.circle.fill")
                                        }
                                        Text(isWriting ? "Adding..." : "Add to Project")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .tint(.orange)
                                .disabled(isWriting)
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // Code Block card
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label("Full License Text", systemImage: "doc.text.fill")
                                        .font(.headline)
                                        .foregroundColor(.gray)
                                    Spacer()
                                }

                                Text(license.body)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .lineSpacing(6)
                                    .padding()
                                    .background(Color.black.opacity(0.2))
                                    .cornerRadius(8)
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                    .padding(24)
                }
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                ContentUnavailableView(
                    "Select a License",
                    systemImage: "doc.text",
                    description: Text("Choose a license from the sidebar to preview and add it to your project.")
                )
            }
        }
        .frame(minWidth: 800, minHeight: 550)
        .alert("License Installation", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            if previewLicense == nil, let first = filteredLicenses.first {
                previewLicense = first
            }
        }
    }

    @MainActor
    private func addLicense(_ license: LicenseTemplate) async {
        isWriting = true
        defer { isWriting = false }

        do {
            let destination = project.directoryURL.appendingPathComponent("LICENSE")
            try license.body.write(to: destination, atomically: true, encoding: .utf8)
            sessionStore.refreshFileTree(for: project)
            alertMessage = "Successfully added the \(license.name) license to your project as 'LICENSE'."
            showAlert = true
        } catch {
            alertMessage = "Failed to add license: \(error.localizedDescription)"
            showAlert = true
        }
    }
}
