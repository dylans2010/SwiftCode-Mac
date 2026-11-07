import Foundation
import YcodeBuild
import YcodeProject

public enum IDEToolActions {
    public typealias Runner = @Sendable (_ arguments: [String], _ cwd: String) -> (status: Int32, output: String)

    public static let inProcess: Runner = { args, cwd in Organizer.run(args, home: NSHomeDirectory(), cwd: cwd) }

    public static func localizationProject(_ model: WorkspaceModel) -> URL? {
        switch model.kind {
        case .package: nil
        case .project: model.url
        case .workspace: model.projects.keys.sorted().first.map { URL(fileURLWithPath: $0) }
        }
    }

    public static func exportLanguages(_ proj: PBXProj?) -> [String] {
        let dev = proj?.project?.string("developmentRegion") ?? "en"
        let known = proj?.project?.references("knownRegions") ?? []
        var out = [dev]
        for r in known where r != "Base" && !out.contains(r) { out.append(r) }
        return out
    }

    public static func exportArguments(project: URL, to directory: URL, languages: [String]) -> [String] {
        ["-exportLocalizations", "-localizationPath", directory.path, "-project", project.path]
            + languages.flatMap { ["-exportLanguage", $0] }
    }

    public static func importArguments(project: URL, from path: URL) -> [String] {
        ["-importLocalizations", "-localizationPath", path.path, "-project", project.path]
    }

    public static func exportFolderName(project: URL) -> String {
        "\(project.deletingPathExtension().lastPathComponent) Localizations"
    }

    public static func createdLocalizations(in output: String) -> [String] {
        let marker = "An xcloc was created at "
        return output.split(separator: "\n").compactMap { line in
            line.range(of: marker).map { String(line[$0.upperBound...]).trimmingCharacters(in: .whitespaces) }
        }
    }

    public static func docbuildArguments(container: BuildRequest.Container, scheme: String) -> (arguments: [String], cwd: String, derivedData: String) {
        let (lead, cwd): ([String], String) = switch container {
        case .project(let p): (["-project", p], URL(fileURLWithPath: p).deletingLastPathComponent().path)
        case .workspace(let p): (["-workspace", p], URL(fileURLWithPath: p).deletingLastPathComponent().path)
        case .package(let d): ([], d)
        }
        let dd = cwd + "/.swiftcode-build/Documentation"
        return (lead + ["-scheme", scheme, "-derivedDataPath", dd, "docbuild"], cwd, dd)
    }

    public static func documentationArchives(derivedData: String) -> [String] {
        let fm = FileManager.default
        let products = derivedData + "/Build/Products"
        var out: [String] = []
        for config in ((try? fm.contentsOfDirectory(atPath: products)) ?? []).sorted() {
            let dir = products + "/" + config
            for name in ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).sorted() where name.hasSuffix(".doccarchive") {
                out.append(dir + "/" + name)
            }
        }
        return out
    }

    public static func derivedDataFolder(buildFolder: URL) -> URL {
        buildFolder.lastPathComponent == "Build" ? buildFolder.deletingLastPathComponent() : buildFolder
    }

    @discardableResult
    public static func deleteDerivedData(_ folder: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return true }
        return (try? fm.removeItem(at: folder)) != nil
    }
}
