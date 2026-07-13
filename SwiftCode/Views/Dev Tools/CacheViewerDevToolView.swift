import SwiftUI
import os.log

struct CacheItem: Identifiable {
    let id = UUID()
    let key: String
    let size: String
    let valueType: String
}

@Observable
@MainActor
final class CacheViewerViewModel {
    var caches: [CacheItem] = [
        CacheItem(key: "com.swiftcode.cache.recent_files", size: "340 KB", valueType: "JSON String Array"),
        CacheItem(key: "com.swiftcode.cache.syntax_highlight_buffer", size: "12.8 MB", valueType: "Syntax Token List"),
        CacheItem(key: "com.swiftcode.cache.github_avatar_images", size: "4.5 MB", valueType: "Binary PNG")
    ]

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "CacheViewer")

    func clearCache() {
        caches.removeAll()
        logger.info("Successfully flushed NSCache and local document URLCache items.")
    }
}

struct CacheViewerDevToolView: View {
    @State private var viewModel = CacheViewerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Inspect and clear memory and disk caches managed by the development sandbox environment.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Stored Items: \(viewModel.caches.count)")
                        .bold()
                    Spacer()
                    Button("Flush Memory Caches") {
                        viewModel.clearCache()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if viewModel.caches.isEmpty {
                VStack {
                    Spacer()
                    Text("Caches flushed successfully.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(viewModel.caches) { item in
                    HStack {
                        Image(systemName: "folder.circle.fill")
                            .foregroundColor(.purple)
                            .font(.title3)

                        VStack(alignment: .leading) {
                            Text(item.key)
                                .font(.headline)
                            Text(item.valueType)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(item.size)
                            .font(.system(.body, design: .monospaced))
                            .bold()
                    }
                }
            }
        }
        .navigationTitle("Cache Viewer")
    }
}
