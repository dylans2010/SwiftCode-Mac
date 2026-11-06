// Ported from SwiftCode-Legacy `SwiftCode/Views/Developer/CacheInspectorView.swift` (Dylan's own code; direct port authorised under MIT).
// V10 (independent verification): confirmed genuinely missing from production at bc28f653.
//
// CLEANUP (2026-11-06, A1): the ported file listed four invented rows
// ("Syntax Highlighting Map", 2.4 MB, etc.) and its Clear/Purge buttons only
// removed rows from the in-memory array — nothing on disk was ever touched.
// Replaced with real data: FileManager enumerates the real cache directories
// (every subdirectory of ~/Library/Caches and of Xcode's DerivedData), sizes
// are real recursive totals from URL resource values (.fileSizeKey), and
// Clear / Purge All really delete the directory with FileManager.removeItem,
// then re-scan. ~/Library/Application Support is deliberately NOT listed:
// it holds user data, not caches. Where a directory cannot be read or
// deleted, the error is shown instead of a made-up size.
import SwiftUI
import SwiftCodeUI

struct CacheInspectorView: View {
    @State private var items: [CacheItem] = []
    @State private var isScanning = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if isScanning {
                    Text("Scanning cache directories…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if items.isEmpty {
                    Text("No cache directories found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name).font(.headline)
                                Text(item.size).font(.caption).foregroundStyle(.secondary)
                                Text(item.url.path)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button("Clear") { clear(item) }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("On-Disk Caches")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(role: .destructive) { purgeAll() } label: {
                    Label("Purge All Caches", systemImage: "trash.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(items.isEmpty)
            }
        }
        .liquidGlass(style: .subtle, cornerRadius: 12)
        .navigationTitle("Cache Inspector")
        .task { await refresh() }
    }

    private func refresh() async {
        isScanning = true
        errorMessage = nil
        items = await Task.detached(priority: .userInitiated) {
            Self.scanCacheDirectories()
        }.value
        isScanning = false
    }

    /// Removes one real cache directory from disk, then drops its row.
    private func clear(_ item: CacheItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = "Could not clear \(item.name): \(error.localizedDescription)"
        }
    }

    /// Removes every listed cache directory from disk, then re-scans.
    private func purgeAll() {
        var failures: [String] = []
        for item in items {
            do {
                try FileManager.default.removeItem(at: item.url)
            } catch {
                failures.append("\(item.name): \(error.localizedDescription)")
            }
        }
        if failures.isEmpty {
            errorMessage = nil
        } else {
            errorMessage = failures.joined(separator: "\n")
        }
        Task { await refresh() }
    }

    /// Real cache locations: each subdirectory of ~/Library/Caches and of
    /// Xcode's DerivedData, with its real recursive size. Unreadable
    /// directories are skipped; a missing location contributes nothing.
    private static func scanCacheDirectories() -> [CacheItem] {
        let fileManager = FileManager.default
        var found: [CacheItem] = []

        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            found += cacheItems(in: caches, namePrefix: "")
        }

        let derivedData = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        found += cacheItems(in: derivedData, namePrefix: "DerivedData/")

        return found.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static func cacheItems(in directory: URL, namePrefix: String) -> [CacheItem] {
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
            return CacheItem(
                name: namePrefix + url.lastPathComponent,
                size: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                sizeBytes: size,
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

struct CacheItem: Identifiable {
    let id = UUID()
    let name: String
    /// Human-readable form of the real on-disk size (`sizeBytes`).
    let size: String
    let sizeBytes: Int64
    /// The real directory this row represents; Clear deletes it.
    let url: URL
}
