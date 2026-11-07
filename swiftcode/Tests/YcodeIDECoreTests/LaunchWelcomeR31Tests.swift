import Foundation
import Testing
import YcodeBuild
import YcodeProject
@testable import YcodeIDECore

@MainActor
@Suite(.serialized) struct LaunchWelcomeR31Tests {
    func tempDir(_ tag: String) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-r31-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u.resolvingSymlinksInPath()
    }

    func sim(_ name: String, _ version: String, platform: String = "iOS") -> Destination {
        Destination(name: name, specifier: "platform=\(platform) Simulator,id=\(name)-\(version)", platform: platform, kind: .simulator,
                    osVersion: version, identifier: "\(name)-\(version)")
    }

    @Test func launchWithoutDocumentsShowsWelcomeNotAnOpenPanel() {
        #expect(LaunchAction.decide(arguments: [], openDocumentCount: 0) == .welcome)
        #expect(LaunchAction.decide(arguments: ["-ApplePersistenceIgnoreState", "YES"], openDocumentCount: 0) == .welcome)
        #expect(LaunchAction.decide(arguments: ["/p/App.xcodeproj"], openDocumentCount: 0) == .open(["/p/App.xcodeproj"]))
        #expect(LaunchAction.decide(arguments: [], openDocumentCount: 1) == .none)
    }

    @Test func recentProjectsOrderLimitPersistenceAndMissingFiles() throws {
        let dir = try tempDir("recents")
        defer { try? FileManager.default.removeItem(at: dir) }
        let td = TestDefaults("r31-recents")
        defer { td.remove() }
        let r = RecentProjects(defaults: td.defaults)
        var urls: [URL] = []
        for i in 0..<12 {
            let u = dir.appendingPathComponent("P\(i).xcodeproj")
            try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            urls.append(u)
            r.note(u)
        }
        #expect(r.urls.count == RecentProjects.limit)
        #expect(r.urls.first?.path == urls[11].path)
        r.note(urls[5])
        #expect(r.urls.first?.path == urls[5].path && r.urls.filter { $0.path == urls[5].path }.count == 1)
        #expect(RecentProjects(defaults: td.defaults).urls.map(\.path) == r.urls.map(\.path))
        let pkg = dir.appendingPathComponent("Pkg")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        try "".write(to: pkg.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        r.note(pkg.appendingPathComponent("Package.swift"))
        #expect(r.urls.first?.path == pkg.path)
        try FileManager.default.removeItem(at: urls[5])
        #expect(!r.urls.map(\.path).contains(urls[5].path))
        r.clear()
        #expect(r.urls.isEmpty)
    }

    @Test func defaultDestinationRule() {
        let sims = [sim("iPad Air", "26.4"), sim("iPhone 17 Pro", "26.4"), sim("iPhone 17", "26.4"), sim("iPhone 18", "27.0"),
                    sim("Apple Vision Pro", "27.0", platform: "visionOS"), sim("iPhone 15", "17.5")]
        #expect(DestinationCatalog.simulatorsInMenuOrder(sims.filter { $0.platform == "iOS" }).map(\.name)
                == ["iPhone 18", "iPhone 17", "iPhone 17 Pro", "iPad Air", "iPhone 15"])
        #expect(DestinationCatalog.defaultDestination(platform: "macOS", deploymentTarget: "15.0", simulators: sims) == .myMac)
        #expect(DestinationCatalog.defaultDestination(platform: nil, deploymentTarget: nil, simulators: sims) == .myMac)
        #expect(DestinationCatalog.defaultDestination(platform: "iOS", deploymentTarget: "18.0", simulators: sims).name == "iPhone 17 Pro")
        #expect(DestinationCatalog.defaultDestination(platform: "iOS", deploymentTarget: "18.0",
                                                      simulators: sims.filter { $0.name != "iPhone 17 Pro" }).name == "iPhone 18")
        #expect(DestinationCatalog.defaultDestination(platform: "iOS", deploymentTarget: "27.1", simulators: sims).name
                == "Any iOS Simulator Device")
        let generic = DestinationCatalog.defaultDestination(platform: "iOS", deploymentTarget: "18.0", simulators: [])
        #expect(generic.specifier == "generic/platform=iOS Simulator" && generic.kind == .generic)
        #expect(DestinationCatalog.compareVersions("26.10", "26.4") == .orderedDescending)
    }

    @Test func packageRootOrder() throws {
        let dir = try tempDir("pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        for f in ["Alpha", "Sources/P", "Tests/PTests", "Docs"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(f), withIntermediateDirectories: true)
        }
        for f in ["Package.swift", "README.md", "Sources/P/P.swift"] {
            try "".write(to: dir.appendingPathComponent(f), atomically: true, encoding: .utf8)
        }
        #expect(NavigatorTree.package(at: dir).children.map(\.name) == ["Package.swift", "Sources", "Tests", "Alpha", "Docs", "README.md"])
    }

    @Test func userStateFileLocation() {
        let p = URL(fileURLWithPath: "/w/App.xcodeproj"), k = URL(fileURLWithPath: "/w/Pkg")
        #expect(WorkspaceUserState.fileURL(container: p, isPackage: false, user: "me").path
                == "/w/App.xcodeproj/xcuserdata/me.xcuserdatad/swiftcode-ui-state.json")
        #expect(WorkspaceUserState.fileURL(container: k, isPackage: true, user: "me").path
                == "/w/Pkg/.swiftpm/xcode/xcuserdata/me.xcuserdatad/swiftcode-ui-state.json")
        var s = WorkspaceUserState()
        for i in 0..<25 { s.noteRecentFile("/f\(i)") }
        s.noteRecentFile("/f10")
        #expect(s.recentFiles.count == WorkspaceUserState.recentFileLimit && s.recentFiles.last == "/f10")
    }
}
