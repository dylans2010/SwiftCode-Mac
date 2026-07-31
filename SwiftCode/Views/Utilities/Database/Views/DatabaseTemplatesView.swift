import SwiftUI

struct DatabaseTemplatesView: View {
    @StateObject private var templateManager = DatabaseTemplateManager.shared
    @State private var searchQuery = ""

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
                                // Applies the template schema automatically
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
    }
}
