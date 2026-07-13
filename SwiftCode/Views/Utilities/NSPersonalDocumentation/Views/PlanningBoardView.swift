import SwiftUI

struct PlanningBoardView: View {
    let coordinator: PersonalDocumentationCoordinator
    let kind: ModuleKind

    @State private var items: [Document] = []
    @State private var showingAddSheet = false
    @State private var newItemTitle = ""

    private let columns = ["To Do", "In Progress", "Done"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.rawValue)
                        .font(.title2.bold())
                    Text("Manage work items, status workflows, and priority pipelines.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HStack(spacing: 16) {
                ForEach(columns, id: \.self) { column in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(column)
                                .font(.headline)
                            Spacer()
                            Text("\(items.filter { $0.status == column }.count)")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .clipShape(Capsule())
                        }

                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(items.filter { $0.status == column }) { item in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(item.title)
                                            .font(.body.bold())

                                        if let priority = item.priority {
                                            Text(priority)
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(priorityColor(priority).opacity(0.15))
                                                .foregroundStyle(priorityColor(priority))
                                                .cornerRadius(4)
                                        }

                                        HStack {
                                            Spacer()
                                            Button {
                                                cycleStatus(of: item)
                                            } label: {
                                                Image(systemName: "arrow.right.circle")
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding()
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(8)
                                    .shadow(radius: 1)
                                    .onTapGesture {
                                        coordinator.selectDocument(item.id)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                    .cornerRadius(10)
                }
            }
            .padding()
        }
        .onAppear {
            loadItems()
        }
        .sheet(isPresented: $showingAddSheet) {
            VStack(spacing: 16) {
                Text("Add Planning Item")
                    .font(.headline)
                TextField("Item Title", text: $newItemTitle)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") {
                        showingAddSheet = false
                    }
                    Button("Save") {
                        if !newItemTitle.isEmpty {
                            _ = try? coordinator.planning.createPlanningItem(title: newItemTitle, kind: kind, status: "To Do", priority: "Medium")
                            newItemTitle = ""
                            showingAddSheet = false
                            loadItems()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }

    private func loadItems() {
        items = (try? coordinator.planning.fetchPlanningItems(for: kind)) ?? []
    }

    private func cycleStatus(of item: Document) {
        if item.status == "To Do" {
            item.status = "In Progress"
        } else if item.status == "In Progress" {
            item.status = "Done"
        } else {
            item.status = "To Do"
        }
        try? coordinator.documents.updateDocument(item)
        loadItems()
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "high": return .red
        case "low": return .gray
        default: return .orange
        }
    }
}
