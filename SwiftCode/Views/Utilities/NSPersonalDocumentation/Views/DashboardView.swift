import SwiftUI

struct DashboardView: View {
    let coordinator: PersonalDocumentationCoordinator
    @State private var snapshot: DashboardManager.DashboardSnapshot? = nil
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personal Documentation Dashboard")
                            .font(.title2.bold())
                        Text("Project-scoped knowledge base, structured records, and workspace insights.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if isLoading {
                    ProgressView()
                        .padding()
                } else if let stats = snapshot {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        statCard(title: "Total Documents", value: "\(stats.totalDocuments)", icon: "doc.text.fill", color: .blue)
                        statCard(title: "Structured Tasks", value: "\(stats.totalTasks)", icon: "slider.horizontal.3", color: .orange)
                        statCard(title: "Completed Tasks", value: "\(stats.completedTasks)", icon: "checkmark.circle.fill", color: .green)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Activity")
                            .font(.headline)

                        if stats.recentDocuments.isEmpty {
                            ContentUnavailableView {
                                Label("No recent documents", systemImage: "doc.text")
                            } description: {
                                Text("Create your first document using the sidebar to get started.")
                            }
                            .frame(height: 150)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(10)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(stats.recentDocuments) { doc in
                                    HStack {
                                        Image(systemName: doc.moduleKind.icon)
                                            .foregroundStyle(doc.moduleKind.accentColor)
                                            .frame(width: 24, height: 24)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(doc.title)
                                                .font(.body.bold())
                                            Text("Updated \(doc.updatedAt, style: .relative) ago")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Button {
                                            coordinator.selectedModuleKind = doc.moduleKind
                                            coordinator.selectedDocumentID = doc.id
                                        } label: {
                                            Text("Open")
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    .padding(12)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            loadDashboard()
        }
    }

    private func loadDashboard() {
        isLoading = true
        Task {
            snapshot = try? await coordinator.dashboard.getSnapshot()
            isLoading = false
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.bold())
            }
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}
