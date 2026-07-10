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
                // Filters Header
                VStack(spacing: 12) {
                    TextField("Search licenses...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .padding(.horizontal)
                        .padding(.top, 12)

                    HStack(spacing: 8) {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categories, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)

                        Picker("Sort", selection: $sortMode) {
                            ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                .background(.background.opacity(0.4))

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
                        NavigationLink(value: license) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(license.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(license.category)
                                        .font(.caption2)
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
                            .padding(.vertical, 4)
                        }
                        .tag(license)
                    }
                }
            }
            .navigationTitle("Add License")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        } detail: {
            // Detailed License Preview & Action Screen
            if let license = previewLicense {
                VStack(spacing: 0) {
                    // Header Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(license.name)
                                .font(.title.bold())
                            HStack(spacing: 8) {
                                Text(license.category)
                                    .font(.subheadline)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.blue)

                                Text("Offline Available")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()

                        Button {
                            Task { await addLicense(license) }
                        } label: {
                            if isWriting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Add to Project", systemImage: "plus.circle.fill")
                                    .font(.headline)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isWriting)
                    }
                    .padding()
                    .background(.background.opacity(0.5))

                    Divider()

                    // License text
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(license.summary)
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 8)

                            Text(license.body)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .lineSpacing(4)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select a License",
                    systemImage: "doc.text",
                    description: Text("Choose a license from the sidebar to preview and add it to your project.")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .alert("License Installation", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            // Default select first license if available
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
            // SAFETY: atomic writes prevent project file corruption
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
