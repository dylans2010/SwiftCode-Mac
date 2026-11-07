import Foundation

public struct GitHubProjectSync: Sendable {
    private let client: GitHubClient

    public init(client: GitHubClient) {
        self.client = client
    }

    @discardableResult
    public func pushDirectory(_ directory: URL, owner: String, repo: String, commitMessage: String, branch: String? = nil) async throws -> Int {
        let files = collectTextFiles(in: directory)
        var pushed = 0
        for file in files {
            let relativePath = file.path.replacingOccurrences(of: directory.path + "/", with: "")
            let content = try String(contentsOf: file, encoding: .utf8)
            let sha = try? await client.getFileSHA(owner: owner, repo: repo, path: relativePath)
            _ = try await client.pushFile(owner: owner, repo: repo, path: relativePath, content: content, message: commitMessage, sha: sha, branch: branch)
            pushed += 1
        }
        return pushed
    }

    @discardableResult
    public func pullFile(owner: String, repo: String, path: String, into directory: URL, ref: String? = nil) async throws -> URL {
        let text = try await client.getFileText(owner: owner, repo: repo, path: path, ref: ref)
        let destination = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    @discardableResult
    public func pullDirectory(owner: String, repo: String, branch: String = "main", into directory: URL) async throws -> Int {
        let tree: [GitHubTreeEntry]
        do {
            tree = try await client.getRepoTree(owner: owner, repo: repo, ref: branch)
        } catch {
            throw GitCommandsError.pullFailed(error.localizedDescription)
        }
        let files = tree.filter { $0.type == "blob" }
        var pulled = 0
        for entry in files {
            do {
                _ = try await pullFile(owner: owner, repo: repo, path: entry.path, into: directory, ref: branch)
                pulled += 1
            } catch {
                throw GitCommandsError.pullFailed(error.localizedDescription)
            }
        }
        return pulled
    }

    public func textFiles(in directory: URL) -> [String] {
        collectTextFiles(in: directory).map { $0.path.replacingOccurrences(of: directory.path + "/", with: "") }
    }

    private func collectTextFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathComponents.contains(".git") { continue }
            guard fileURL.pathExtension.lowercased() != "png",
                  fileURL.pathExtension.lowercased() != "jpg",
                  fileURL.pathExtension.lowercased() != "jpeg",
                  fileURL.pathExtension.lowercased() != "gif",
                  fileURL.pathExtension.lowercased() != "icns",
                  fileURL.pathExtension.lowercased() != "zip" else { continue }
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard (try? String(contentsOf: fileURL, encoding: .utf8)) != nil else { continue }
            files.append(fileURL)
        }
        return files.sorted(by: { $0.path < $1.path })
    }
}
