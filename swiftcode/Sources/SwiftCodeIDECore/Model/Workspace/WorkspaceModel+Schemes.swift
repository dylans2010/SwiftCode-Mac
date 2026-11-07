import Foundation
import SwiftCodeProject
import SwiftCodeWorkspace

extension WorkspaceModel {
    public var schemeContainers: [URL] {
        switch kind {
        case .project: [url]
        case .workspace: [url] + projects.keys.sorted().map { URL(fileURLWithPath: $0) }
        case .package: []
        }
    }

    public func loadSchemes() -> [Scheme] {
        schemeContainers.flatMap { Scheme.discover(in: $0) }
    }

    public var configurationNames: [String] {
        var seen = Set<String>()
        let names = projects.keys.sorted().flatMap { path -> [String] in
            let p = projects[path]!
            return p.buildConfigurations(listID: p.project?.string("buildConfigurationList")).compactMap { $0.string("name") }
        }
        let unique = names.filter { seen.insert($0).inserted }
        return unique.isEmpty ? ["Debug", "Release"] : unique
    }
}
