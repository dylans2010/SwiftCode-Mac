import Foundation

public enum AssistToolingSupport {
    public static func resolvePath(_ path: String?, workspaceRoot: URL) -> URL {
        let rawPath = (path?.isEmpty == false ? path! : ".")
        if rawPath == "." { return workspaceRoot }
        return workspaceRoot.appendingPathComponent(rawPath)
    }

    public static func relativePath(for url: URL, workspaceRoot: URL) -> String {
        let root = workspaceRoot.path
        if url.path.hasPrefix(root + "/") {
            return String(url.path.dropFirst(root.count + 1))
        }
        return url.lastPathComponent
    }

    public static func enumeratedFiles(at root: URL, allowedExtensions: Set<String>? = nil, maxFileSize: Int = 300_000) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else {
                continue
            }
            if let size = values.fileSize, size > maxFileSize { continue }
            if let allowedExtensions {
                let ext = fileURL.pathExtension.lowercased()
                if !allowedExtensions.contains(ext) { continue }
            }
            files.append(fileURL)
        }
        return files
    }

    public static func isCodeFile(_ fileURL: URL) -> Bool {
        let codeExtensions: Set<String> = ["swift", "m", "mm", "h", "hpp", "c", "cpp", "js", "ts", "tsx", "jsx", "py", "rb", "java", "kt", "go", "rs"]
        return codeExtensions.contains(fileURL.pathExtension.lowercased())
    }

    public static func readText(_ url: URL) -> String? {
        return try? String(contentsOf: url, encoding: .utf8)
    }

    public static func keywordOccurrences(in content: String, keywords: [String]) -> Int {
        keywords.reduce(0) { partial, keyword in
            partial + content.components(separatedBy: keyword).count - 1
        }
    }
}
