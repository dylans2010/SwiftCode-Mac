import Foundation

/// `project-inspector` tool (Legacy `Sources/Tools/ProjectInspector/main.swift`).
///
/// Inspects a project directory and prints its metadata as pretty-printed,
/// key-sorted JSON. Library entry point: the executable target wraps it in
/// a thin `@main` that calls `exit(ProjectInspectorMain.run(...))`.
public enum ProjectInspectorMain {
    public static func run(arguments: [String]) -> Int32 {
        let path = arguments.first ?? FileManager.default.currentDirectoryPath

        let inspector = ProjectInspector()
        do {
            let metadata = try inspector.inspect(at: path)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(metadata)
            print(String(decoding: data, as: UTF8.self))
            return 0
        } catch {
            print("Error inspecting project: \(error.localizedDescription)")
            return 1
        }
    }
}
