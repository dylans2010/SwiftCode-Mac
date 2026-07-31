import SwiftUI

struct DatabaseTemplatesView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @StateObject private var templateManager = DatabaseTemplateManager.shared
    @State private var searchQuery = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false

    var filteredTemplates: [DatabaseTemplate] {
        if searchQuery.isEmpty { return templateManager.templates }
        return templateManager.templates.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery) ||
            $0.description.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search templates...", text: $searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding()
            .background(Color.secondary.opacity(0.06))

            Divider()

            // Templates Grid List
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                    ForEach(filteredTemplates) { template in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .foregroundColor(.blue)
                                Text(template.name)
                                    .font(.headline)
                                Spacer()
                                Button(action: { templateManager.toggleFavorite(template) }) {
                                    Image(systemName: template.isFavorite ? "star.fill" : "star")
                                        .foregroundColor(.yellow)
                                }
                                .buttonStyle(.plain)
                            }

                            Text(template.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(3)

                            HStack {
                                ForEach(template.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.system(size: 8))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.12), in: Capsule())
                                }
                            }

                            Button("Apply Template") {
                                applyTemplate(template)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .alert("Schema Status", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func applyTemplate(_ template: DatabaseTemplate) {
        guard let conn = connManager.activeConnection else {
            alertMessage = "No active database connection selected. Please activate a connection first."
            showingAlert = true
            return
        }

        Task {
            var appliedCount = 0
            var errorOccurred = false
            var lastErrorMessage = ""

            for table in template.tables {
                do {
                    try await DatabaseSchemaManager.shared.createTable(connection: conn, table: table)
                    appliedCount += 1
                } catch {
                    errorOccurred = true
                    lastErrorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                if errorOccurred {
                    alertMessage = "Successfully applied \(appliedCount) tables. Error applying remaining: \(lastErrorMessage)"
                } else {
                    alertMessage = "Successfully applied \(appliedCount) tables from template '\(template.name)' to connection '\(conn.name)'!"
                }
                showingAlert = true
            }
        }
    }
}
