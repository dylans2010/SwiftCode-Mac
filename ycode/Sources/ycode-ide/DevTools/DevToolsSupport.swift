import Foundation
import SwiftUI

/// Placeholder shown by a ported tool on a platform where its system
/// framework is unavailable (e.g. a CryptoKit tool on Linux). The tool
/// keeps its name in the catalogue so the gap is visible, instead of
/// silently disappearing or showing invented values.
struct DevToolsUnavailableView: View {
    let reason: String

    var body: some View {
        ContentUnavailableView(
            "Not Available on This Platform",
            systemImage: "exclamationmark.triangle",
            description: Text(reason)
        )
    }
}

/// Real directory-size helpers for the ported disk/cache tools. Legacy's
/// disk and cache views listed hardcoded sizes ("4.8 GB", "340 KB") and
/// their Clean buttons only rewrote the label; these helpers measure the
/// live filesystem instead.
enum DevToolsDiskUsage {
    /// Total allocated size of everything under `url`, in bytes.
    static func allocatedSize(of url: URL) -> Int64? {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var total: Int64 = 0
        var sawAny = false
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isDirectory != true else { continue }
            sawAny = true
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return sawAny ? total : nil
    }

    /// Human-readable byte count (e.g. "4.8 GB").
    static func formatted(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
