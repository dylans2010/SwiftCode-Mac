import Foundation
import SwiftCodeBuild

extension WorkspaceSession {
    public var latestCoverage: [CoverageItem] {
        reports.first { !$0.context.coverage.isEmpty }?.context.coverage ?? []
    }

    public func coverageLineCounts(file: String) -> [Int]? {
        let want = IssueMerge.canonicalPath(file)
        for target in latestCoverage {
            for f in target.files {
                guard let p = f.path, let counts = f.lineCounts, IssueMerge.canonicalPath(p) == want else { continue }
                return counts
            }
        }
        return nil
    }

    public static func coverageMarks(_ counts: [Int]?) -> [Int: Int] {
        guard let counts else { return [:] }
        var m: [Int: Int] = [:]
        for (i, c) in counts.enumerated() where c >= 0 { m[i + 1] = c }
        return m
    }
}
