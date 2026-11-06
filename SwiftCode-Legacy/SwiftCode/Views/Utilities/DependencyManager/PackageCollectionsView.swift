import SwiftUI

struct PackageCollectionsView: View {
    @State private var platformManager = DependencyPlatformManager.shared

    @State private var newName: String = ""
    @State private var newDescription: String = ""
    @State private var newCategory: String = "Networking"
    @State private var showCreateSheet = false

    @State private var importJSON: String = ""
    @State private var showImportAlert = false
    @State private var importError: String?

    let categories = ["Networking", "Database", "UI", "Utility", "Analytics", "Cryptography"]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Info and Global Actions Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Custom Packages Workspaces & Collections", systemImage: "folder.fill")
                                .font(.title2.bold())
                                .foregroundColor(.orange)
                            Spacer()
                        }

                        Text("Organize libraries into reusable development templates and project presets.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Divider()

                        HStack(spacing: 12) {
                            Button("Export Collections") {
                                exportToClipboard()
                            }
                            .buttonStyle(.bordered)

                            Button("Import Collection...") {
                                showImportAlert = true
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button {
                                showCreateSheet = true
                            } label: {
                                Label("New Workspace Group", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Custom Workspaces / Presets Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Custom Workspaces / Presets", systemImage: "folder.badge.gearshape")
                            .font(.headline)
                            .foregroundColor(.blue)

                        if platformManager.collections.isEmpty {
                            ContentUnavailableView(
                                "No Custom Workspaces",
                                systemImage: "folder.badge.questionmark",
                                description: Text("Create your own modular development presets (e.g. Core Database, Utility toolkit) above.")
                            )
                            .padding(.vertical, 16)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: .infinity))], spacing: 16) {
                                ForEach(platformManager.collections) { col in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text(col.name)
                                                .font(.headline)
                                            Spacer()
                                            Text(col.category)
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.blue.opacity(0.12), in: Capsule())
                                        }

                                        Text(col.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .frame(height: 36, alignment: .topLeading)

                                        Divider()

                                        HStack {
                                            Label("\(col.packageURLs.count) packages", systemImage: "puzzlepiece.extension")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Button {
                                                removeCollection(col.id)
                                            } label: {
                                                Image(systemName: "trash")
                                                    .foregroundStyle(.red)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding()
                                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Quick Favorites Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Quick Favorites List", systemImage: "star.fill")
                            .font(.headline)
                            .foregroundColor(.yellow)

                        if platformManager.favoritePackages.isEmpty {
                            Text("No favorites pinned yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 12)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(platformManager.favoritePackages, id: \.self) { url in
                                    let name = url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? url
                                    HStack {
                                        Text(name)
                                            .font(.subheadline.bold())
                                        Spacer()
                                        Button {
                                            platformManager.toggleFavorite(url: url)
                                        } label: {
                                            Image(systemName: "star.fill")
                                                .foregroundStyle(.yellow)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(10)
                                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Ecosystem Watchlist Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Ecosystem Watchlist", systemImage: "eye.fill")
                            .font(.headline)
                            .foregroundColor(.purple)

                        if platformManager.watchlistPackages.isEmpty {
                            Text("No packages on watchlist.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 12)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(platformManager.watchlistPackages, id: \.self) { url in
                                    let name = url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? url
                                    HStack {
                                        Text(name)
                                            .font(.subheadline.bold())
                                        Spacer()
                                        Button {
                                            platformManager.toggleWatchlist(url: url)
                                        } label: {
                                            Image(systemName: "eye.fill")
                                                .foregroundStyle(.purple)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(10)
                                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .navigationTitle("Presets & Collections")
        .sheet(isPresented: $showCreateSheet) {
            VStack(spacing: 16) {
                Text("Create Workspace Collection")
                    .font(.headline)

                TextField("Collection Name", text: $newName)
                    .textFieldStyle(.roundedBorder)

                TextField("Short Description", text: $newDescription)
                    .textFieldStyle(.roundedBorder)

                Picker("Category Tag", selection: $newCategory) {
                    ForEach(categories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Button("Cancel") {
                        showCreateSheet = false
                    }
                    .buttonStyle(.bordered)

                    Button("Create") {
                        platformManager.createCollection(name: newName, description: newDescription, category: newCategory)
                        showCreateSheet = false
                        newName = ""
                        newDescription = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 320)
        }
        .sheet(isPresented: $showImportAlert) {
            VStack(spacing: 16) {
                Text("Import Collection Preset")
                    .font(.headline)

                TextEditor(text: $importJSON)
                    .frame(height: 120)
                    .border(Color.secondary.opacity(0.2))

                if let error = importError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                HStack {
                    Button("Cancel") {
                        showImportAlert = false
                        importJSON = ""
                        importError = nil
                    }
                    .buttonStyle(.bordered)

                    Button("Import") {
                        runImport()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(importJSON.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 400)
        }
    }

    private func exportToClipboard() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(platformManager.collections),
           let str = String(data: data, encoding: .utf8) {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([.string], owner: nil)
            pasteboard.setString(str, forType: .string)
        }
    }

    private func runImport() {
        guard let data = importJSON.data(using: .utf8) else {
            importError = "Invalid UTF8 payload."
            return
        }

        do {
            let decoded = try JSONDecoder().decode([PackageCollection].self, from: data)
            platformManager.collections.append(contentsOf: decoded)
            platformManager.saveState()
            showImportAlert = false
            importJSON = ""
            importError = nil
        } catch {
            importError = "Decoding failed: \(error.localizedDescription)"
        }
    }

    private func removeCollection(_ id: UUID) {
        platformManager.collections.removeAll { $0.id == id }
        platformManager.saveState()
    }
}
