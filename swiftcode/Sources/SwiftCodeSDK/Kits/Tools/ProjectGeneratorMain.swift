import Foundation

/// `project-generator` tool (Legacy `Sources/Tools/ProjectGenerator/main.swift`).
///
/// `project-generator <type> <name> [--out <dir>]`. Library entry point:
/// the executable target wraps it in a thin `@main` that calls
/// `exit(ProjectGeneratorMain.run(...))`.
public enum ProjectGeneratorMain {
    public static func run(arguments: [String]) -> Int32 {
        let args = arguments
        guard !args.isEmpty else {
            print("Usage: project-generator <type> <name> [--out <dir>]")
            return 1
        }

        let typeStr = args[0]
        guard let type = ProjectType(rawValue: typeStr) else {
            print("Error: Unknown project type '\(typeStr)'.")
            print("Supported types: \(ProjectType.allCases.map { $0.rawValue }.joined(separator: ", "))")
            return 1
        }

        let name = args.count > 1 && !args[1].hasPrefix("-") ? args[1] : "Generated\(type.displayName)"
        var outDir = FileManager.default.currentDirectoryPath
        if let outIdx = args.firstIndex(of: "--out"), outIdx + 1 < args.count {
            outDir = args[outIdx + 1]
        } else if args.count > 1 && !args[1].hasPrefix("-") {
            outDir = (outDir as NSString).appendingPathComponent(name)
        }

        let coordinator = SwiftCodeSDKCoordinator()
        let opts = ProjectGeneratorOptions(type: type, name: name, identifier: "com.swiftcode.\(name.lowercased())", destinationDirectory: outDir)
        do {
            let meta = try coordinator.projectGenerator.generate(options: opts)
            print("Project generated at \(meta.rootPath) (\(meta.type.displayName))")
            return 0
        } catch {
            print("Generation error: \(error.localizedDescription)")
            return 1
        }
    }
}
