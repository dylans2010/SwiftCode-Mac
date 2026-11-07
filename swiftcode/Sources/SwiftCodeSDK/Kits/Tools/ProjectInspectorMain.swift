import Foundation

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
