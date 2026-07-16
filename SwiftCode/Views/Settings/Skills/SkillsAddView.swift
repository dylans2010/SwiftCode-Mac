import SwiftUI
import UniformTypeIdentifiers

struct SkillsAddView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var manager = AgentSkillManager.shared

    @State private var showImporter = false
    @State private var importError: String?

    // Sheets/Modals controllers
    @State private var showCreateManual = false
    @State private var showDraftWithAI = false
    @State private var showBrowseLibrary = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Block
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.12))
                                .frame(width: 56, height: 56)
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 30))
                                .foregroundColor(.orange)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Extend Agent Capabilities")
                                .font(.title2.bold())
                            Text("Instruct the AI agent with specific guidelines, patterns, and code examples.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    Divider()

                    // Workflows Options Grid (Adaptive layout)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 400))], spacing: 20) {
                        // 1. Manual Creation Card
                        Button {
                            showCreateManual = true
                        } label: {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Label("Make One", systemImage: "pencil.line")
                                            .font(.headline)
                                            .foregroundColor(.blue)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .foregroundColor(.secondary)
                                    }

                                    Text("Author local rules and patterns using our specialized system markdown and metadata editor.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .frame(height: 50, alignment: .top)
                                }
                                .padding(.vertical, 8)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }
                        .buttonStyle(.plain)

                        // 2. Draft with AI Card
                        Button {
                            showDraftWithAI = true
                        } label: {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Label("Draft with AI", systemImage: "sparkles")
                                            .font(.headline)
                                            .foregroundColor(.purple)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .foregroundColor(.secondary)
                                    }

                                    Text("Briefly prompt our AI assistant to write a professional, pre-compiled skill guide with structured rules.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .frame(height: 50, alignment: .top)
                                }
                                .padding(.vertical, 8)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }
                        .buttonStyle(.plain)

                        // 3. Browse Skills Card
                        Button {
                            showBrowseLibrary = true
                        } label: {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Label("Browse Skills", systemImage: "books.vertical.fill")
                                            .font(.headline)
                                            .foregroundColor(.green)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .foregroundColor(.secondary)
                                    }

                                    Text("Explore our standard bundled library of 20 professional preset guides for core iOS development APIs.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .frame(height: 50, alignment: .top)
                                }
                                .padding(.vertical, 8)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }
                        .buttonStyle(.plain)
                    }

                    // 4. Archive Upload Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Import Custom Skill Archive (.zip)", systemImage: "archivebox.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            Text("Drop or select a zip containing your pre-authored rules.md and scheme.json structure files to upload directly.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button {
                                    showImporter = true
                                } label: {
                                    Label("Import Zipped Archive", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.bordered)

                                if let importError {
                                    Text(importError)
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .navigationTitle("Add Skills")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreateManual) {
                CreateSkillView()
            }
            .sheet(isPresented: $showDraftWithAI) {
                DraftSkillWithAIView()
                    .environmentObject(settings)
            }
            .sheet(isPresented: $showBrowseLibrary) {
                BrowseSkillsView()
            }
            .sheet(isPresented: $showImporter) {
                FileImporterRepresentableView(
                    allowedContentTypes: [.zip],
                    allowsMultipleSelection: false
                ) { urls in
                    showImporter = false
                    guard let url = urls.first else { return }
                    do {
                        try manager.importSkillArchive(at: url)
                        importError = nil
                    } catch {
                        importError = error.localizedDescription
                    }
                }
            }
        }
    }
}
