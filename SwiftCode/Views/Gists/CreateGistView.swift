import SwiftUI

struct CreateGistView: View {
    @EnvironmentObject private var gistService: GitHubGistService
    @Environment(\.dismiss) private var dismiss

    @State private var description = ""
    @State private var isPublic = false
    @State private var files: [GistFile]
    @State private var selectedFileID: UUID?

    init(initialFilename: String? = nil, initialContent: String = "") {
        _description = State(initialValue: "")
        _isPublic = State(initialValue: false)
        let initialFile = GistFile(filename: initialFilename ?? "untitled.swift", content: initialContent)
        _files = State(initialValue: [initialFile])
        _selectedFileID = State(initialValue: initialFile.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Metadata Details Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Gist Details", systemImage: "info.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Description")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Enter gist description...", text: $description)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Toggle("Make Gist Public", isOn: $isPublic)
                                .font(.body)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Files Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Gist Files", systemImage: "doc.text.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()

                                Button(action: {
                                    files.append(GistFile(filename: "file.swift", content: ""))
                                }) {
                                    Label("Add File", systemImage: "plus")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            if files.isEmpty {
                                Text("Add at least one file to create your gist.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                VStack(spacing: 16) {
                                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                TextField("Filename (e.g., script.py)", text: Binding(
                                                    get: { files[index].filename },
                                                    set: { files[index].filename = $0 }
                                                ))
                                                .font(.system(.body, design: .monospaced))
                                                .textFieldStyle(.roundedBorder)

                                                Button(role: .destructive) {
                                                    files.remove(at: index)
                                                } label: {
                                                    Image(systemName: "trash")
                                                        .foregroundStyle(.red)
                                                }
                                                .buttonStyle(.plain)
                                            }

                                            TextEditor(text: Binding(
                                                get: { files[index].content },
                                                set: { files[index].content = $0 }
                                            ))
                                            .font(.system(.body, design: .monospaced))
                                            .frame(minHeight: 180)
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                                        }
                                        .padding(10)
                                        .background(Color.secondary.opacity(0.04))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .navigationTitle("New Gist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            try? await gistService.createGist(files: files, description: description, isPublic: isPublic)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(description.isEmpty || files.isEmpty)
                }
            }
        }
        .frame(width: 650, height: 600)
    }
}
