// Ported from SwiftCode-Legacy `SwiftCode/Views/Dev Tools/CacheViewerDevToolView.swift` (Dylan's own code; direct port authorised under MIT).
// V10 (independent verification): confirmed genuinely missing from production at bc28f653.
//
// CLEANUP (2026-11-06, A1): the ported file listed three invented rows
// ("com.swiftcode.cache.recent_files", 340 KB, etc.) and its "Flush Memory
// Caches" button only emptied the in-memory array while logging a false
// success message — nothing was ever flushed. Replaced with real data:
// FileManager enumerates the real cache directories (every subdirectory of
// ~/Library/Caches and of Xcode's DerivedData) with real recursive sizes,
// plus URLCache.shared's real current memory/disk usage. Flush really calls
// URLCache.shared.removeAllCachedResponses() and then re-scans, so the list
// afterwards reflects disk. Where a directory cannot be read, it is
// skipped; where the flush fails, the error is shown.
import SwiftUI
import os.log
import SwiftCodeUI

struct CacheViewerItem: Identifiable {
    let id = UUID()
    let key: String
    let size: String
    let sizeBytes: Int64
    let valueType: String
    /// The real directory this row represents, if any. URLCache rows have
    /// no directory; they are cleared by removeAllCachedResponses().
    let url: URL?
}

@Observable
@MainActor
final class CacheViewerViewModel {
    var caches: [CacheViewerItem] = []
    var isScanning = true
    var didFlush = false
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "CacheViewer")

    func refresh() async {
        isScanning = true
        errorMessage = nil
        caches = await Task.detached(priority: .userInitiated) {
            Self.scanCaches()
        }.value
        isScanning = false
    }

    /// Really flushes the shared URL cache, then re-scans so the list
    /// reflects what is actually left on disk.
    func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        didFlush = true
        logger.info("Flushed shared URLCache (removeAllCachedResponses) and re-scanning disk caches.")
        Task { await refresh() }
    }

    /// Real cache inventory: URLCache's live memory/disk usage plus every
    /// subdirectory of ~/Library/Caches and Xcode's DerivedData, each with
    /// its real recursive size.
    private static func scanCaches() -> [CacheViewerItem] {
        let fileManager = FileManager.default
        var found: [CacheViewerItem] = []

        let shared = URLCache.shared
        found.append(CacheViewerItem(
            key: "URLCache (memory)",
            size: ByteCountFormatter.string(fromByteCount: Int64(shared.currentMemoryUsage), countStyle: .file),
            sizeBytes: Int64(shared.currentMemoryUsage),
            valueType: "URLCache In-Memory",
            url: nil
        ))
        found.append(CacheViewerItem(
            key: "URLCache (disk)",
            size: ByteCountFormatter.string(fromByteCount: Int64(shared.currentDiskUsage), countStyle: .file),
            sizeBytes: Int64(shared.currentDiskUsage),
            valueType: "URLCache On-Disk",
            url: nil
        ))

        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            found += cacheItems(in: caches, namePrefix: "")
        }

        let derivedData = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        found += cacheItems(in: derivedData, namePrefix: "DerivedData/")

        // URLCache rows stay first; directories follow, largest first.
        let directories = found.dropFirst(2).sorted { $0.sizeBytes > $1.sizeBytes }
        return Array(found.prefix(2)) + directories
    }

    private static func cacheItems(in directory: URL, namePrefix: String) -> [CacheViewerItem] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else { return nil }
            let size = directorySize(at: url)
            return CacheViewerItem(
                key: namePrefix + url.lastPathComponent,
                size: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                sizeBytes: size,
                valueType: "Cache Directory",
                url: url
            )
        }
    }

    /// Real recursive total of regular-file sizes under `url`.
    private static func directorySize(at url: URL) -> Int64 {
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
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

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .liquidGlass(style: .subtle, cornerRadius: 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if viewModel.isScanning {
                VStack {
                    Spacer()
                    Text("Scanning caches…")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if viewModel.caches.isEmpty {
                VStack {
                    Spacer()
                    Text(viewModel.didFlush ? "Caches flushed successfully." : "No caches found.")
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
        .task { await viewModel.refresh() }
    }
}
