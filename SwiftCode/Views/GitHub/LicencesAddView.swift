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
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

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
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(license.name)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Spacer()
                                Text(license.category)
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15), in: Capsule())
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
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
        } detail: {
            // Detailed License Preview Card System
            if let license = previewLicense {
                ScrollView {
                    VStack(spacing: 24) {
                        // Card 1: Header / Title Card
                        GroupBox {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(license.name)
                                        .font(.title2.bold())

                                    HStack(spacing: 12) {
                                        Text(license.category)
                                            .font(.caption.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.blue.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.blue)

                                        Label("Offline Available", systemImage: "wifi.slash")
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
                                .tint(.orange)
                                .disabled(isWriting)
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // Card 2: Summary Card
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Summary", systemImage: "doc.text.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)

                                Text(license.summary)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // Card 3: License Body Card
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("License Template Body", systemImage: "scroll.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)

                                Text(license.body)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .lineSpacing(6)
                                    .padding()
                                    .background(Color.black.opacity(0.15))
                                    .cornerRadius(8)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
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
