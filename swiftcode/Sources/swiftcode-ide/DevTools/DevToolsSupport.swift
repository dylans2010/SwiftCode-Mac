import Foundation
import SwiftUI

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

enum DevToolsDiskUsage {
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

    static func formatted(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
