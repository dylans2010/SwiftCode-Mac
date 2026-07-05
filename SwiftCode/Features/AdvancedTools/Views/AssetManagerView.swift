import SwiftUI
import UniformTypeIdentifiers

struct AssetManagerView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @State private var importedAssets: [URL] = []
    @State private var isImporting = false
    @State private var importError: String?

    private var appIconSizes: [Int] { [20, 29, 40, 60, 76, 83, 1024] }
    private var missingSizes: [Int] {
        let names = Set(importedAssets.map { $0.lastPathComponent.lowercased() })
        return appIconSizes.filter { size in !names.contains(where: { $0.contains("\(size)") }) }
    }

    var body: some View {
        AdvancedToolScreen(title: "Asset Manager") {
            AdvancedToolCard(title: "Asset Intake") {
                Button("Import Images") { isImporting = true }
                    .buttonStyle(.borderedProminent)
                if let importError {
                    Text(importError).font(.caption).foregroundStyle(.red)
                }
            }

            AdvancedToolCard(title: "App Icon Validation") {
                Text(missingSizes.isEmpty ? "All common app icon sizes detected." : "Missing sizes: \(missingSizes.map(String.init).joined(separator: ", "))")
            }

            AdvancedToolCard(title: "Assets") {
                if importedAssets.isEmpty {
                    Text("No Assets Imported").foregroundStyle(.secondary)
                }
                ForEach(importedAssets, id: \.path) { asset in
                    HStack {
                        Image(systemName: "photo")
                        Text(asset.lastPathComponent)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: (try? asset.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
        }
        .onAppear(perform: reloadAssets)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importAssets(urls)
            case .failure(let error): importError = error.localizedDescription
            }
        }
    }

    private func reloadAssets() {
        importError = nil
        guard let project = projectManager.activeProject else { importedAssets = []; return }
        let assetsURL = project.directoryURL.appendingPathComponent("Assets")
        let files = (try? FileManager.default.contentsOfDirectory(at: assetsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        importedAssets = files.filter { ["png", "jpg", "jpeg", "gif", "heic"].contains($0.pathExtension.lowercased()) }
    }

    private func importAssets(_ urls: [URL]) {
        guard let project = projectManager.activeProject else {
            importError = "Open a project before importing assets."
            return
        }

        do {
            let assetsURL = project.directoryURL.appendingPathComponent("Assets")
            try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
            for source in urls {
                let dest = assetsURL.appendingPathComponent(source.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                try FileManager.default.copyItem(at: source, to: dest)
            }
            reloadAssets()
        } catch {
            importError = error.localizedDescription
        }
    }
}
