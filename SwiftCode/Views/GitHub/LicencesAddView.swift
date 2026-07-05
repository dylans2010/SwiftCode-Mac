import SwiftUI

struct LicencesAddView: View {
    let project: Project

    enum SortMode: String, CaseIterable {
        case nameAZ = "Name A-Z"
        case nameZA = "Name Z-A"
        case category = "Category"
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var projectManager: ProjectManager

    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var sortMode: SortMode = .nameAZ
    @State private var selectedLicense: LicenseTemplate?
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

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = searchText.lowercased()
            values = values.filter { $0.name.lowercased().contains(q) || $0.summary.lowercased().contains(q) }
        }

        switch sortMode {
        case .nameAZ: values.sort { $0.name < $1.name }
        case .nameZA: values.sort { $0.name > $1.name }
        case .category: values.sort { ($0.category, $0.name) < ($1.category, $1.name) }
        }
        return values
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Filters") {
                    TextField("Search licenses", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }

                    Picker("Sort", selection: $sortMode) {
                        ForEach(SortMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }

                Section("Available Licenses") {
                    ForEach(filteredLicenses) { license in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(license.name).font(.headline)
                                Spacer()
                                Text(license.category)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.14), in: Capsule())
                            }

                            Text(license.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button("Preview") { selectedLicense = license }
                                    .buttonStyle(.bordered)

                                Button {
                                    Task { await addLicense(license) }
                                } label: {
                                    if isWriting {
                                        ProgressView()
                                    } else {
                                        Text("Add to Project")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isWriting)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Add Licenses")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $selectedLicense) { license in
                NavigationStack {
                    ScrollView {
                        Text(license.body)
                            .font(.system(.footnote, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .navigationTitle(license.name)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { selectedLicense = nil }
                        }
                    }
                }
            }
            .alert("License", isPresented: $showAlert) {
                Button("OK") {}
            } message: {
                Text(alertMessage)
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
            projectManager.refreshFileTree(for: project)
            alertMessage = "\(license.name) license added to project as LICENSE."
            showAlert = true
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}
