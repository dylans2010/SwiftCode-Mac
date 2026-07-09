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
            VStack(spacing: 0) {
                Form {
                    Section("Details") {
                        TextField("Description", text: $description)
                        Toggle("Public Gist", isOn: $isPublic)
                    }

                    Section("Files") {
                        ForEach($files) { $file in
                            VStack(alignment: .leading) {
                                TextField("Filename", text: $file.filename)
                                    .font(.system(.body, design: .monospaced))
                                    .textFieldStyle(.roundedBorder)

                                TextEditor(text: $file.content)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minHeight: 200)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { indices in
                            files.remove(atOffsets: indices)
                        }

                        Button(action: {
                            files.append(GistFile(filename: "file.swift", content: ""))
                        }) {
                            Label("Add File", systemImage: "plus")
                        }
                    }
                }
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
                    .disabled(description.isEmpty || files.isEmpty)
                }
            }
        }
        .frame(width: 600, height: 600)
    }
}
