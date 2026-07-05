import SwiftUI

struct FileSystemInspectorView: View {
    @State private var files: [URL] = []

    var body: some View {
        List {
            ForEach(files, id: \.self) { url in
                VStack(alignment: .leading) {
                    Text(url.lastPathComponent)
                        .font(.subheadline)
                    Text(url.path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        try? FileManager.default.removeItem(at: url)
                        loadFiles()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("FileSystem Inspector")
        .onAppear(perform: loadFiles)
        .toolbar {
            Button("Refresh") {
                loadFiles()
            }
        }
    }

    private func loadFiles() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let contents = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            files = contents
        }
    }
}
