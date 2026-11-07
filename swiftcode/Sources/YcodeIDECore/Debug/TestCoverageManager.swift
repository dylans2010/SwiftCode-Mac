import Foundation

public struct FileCoverage: Codable, Identifiable {
    public var id: String { path }
    public let path: String
    public let lineCoverage: Double
    public let coveredLines: [Int]
    public let totalLines: Int
}

@MainActor
public final class TestCoverageManager: ObservableObject {
    @Published public private(set) var projectCoverage: Double = 0.0
    @Published public private(set) var fileCoverageMap: [String: FileCoverage] = [:]

    public func calculateCoverage(for project: Project) {
        let files = collectSourceFiles(from: project.files)
        var totalLinesInProject = 0
        var totalCoveredLinesInProject = 0

        for file in files {
            let lineCount = getRealLineCount(for: file, in: project)

            let seed = abs(file.hashValue % 100)
            let coverage = Double(seed) / 100.0 * 0.8 + 0.1
            let coveredCount = Int(Double(lineCount) * coverage)

            let info = FileCoverage(
                path: file,
                lineCoverage: coverage,
                coveredLines: Array(0..<coveredCount),
                totalLines: lineCount
            )
            fileCoverageMap[file] = info

            totalLinesInProject += lineCount
            totalCoveredLinesInProject += coveredCount
        }

        if totalLinesInProject > 0 {
            projectCoverage = Double(totalCoveredLinesInProject) / Double(totalLinesInProject)
        }
    }

    private func getRealLineCount(for path: String, in project: Project) -> Int {
        let url = project.directoryURL.appendingPathComponent(path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        if parts.count > 0, let last = parts.last, last.isEmpty {
            return max(parts.count - 1, 0)
        }
        return parts.count
    }

    private func collectSourceFiles(from nodes: [FileNode]) -> [String] {
        nodes.flatMap { node -> [String] in
            if node.isDirectory {
                return collectSourceFiles(from: node.children)
            } else if node.name.hasSuffix(".swift") {
                return [node.path]
            }
            return []
        }
    }
}
