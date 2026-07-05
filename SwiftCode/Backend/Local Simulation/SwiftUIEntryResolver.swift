import Foundation

final class SwiftUIEntryResolver {
    func resolve(projectStructure: ProjectStructure, preferredView: String?) throws -> SimulationEntry {
        if let preferredView, projectStructure.swiftUIViewTypes.contains(preferredView) {
            return SimulationEntry(appName: "View Preview", rootViewType: preferredView, sceneType: "WindowGroup")
        }

        guard let entryFile = projectStructure.appEntryPoint else {
            throw SimulationError(type: .resolve, message: "No @main App entry point was found.", file: nil, line: nil, stackTrace: nil)
        }

        let source = try String(contentsOf: entryFile, encoding: .utf8)
        let appName = firstMatch(in: source, pattern: #"@main\s+struct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*App"#) ?? "SimulationApp"

        guard let rootView = firstMatch(in: source, pattern: #"WindowGroup\s*\{[\s\S]*?([A-Za-z_][A-Za-z0-9_]*)\s*\("#) else {
            throw SimulationError(type: .resolve, message: "Unable to resolve initial View from WindowGroup.", file: entryFile.path, line: nil, stackTrace: nil)
        }

        return SimulationEntry(appName: appName, rootViewType: rootView, sceneType: "WindowGroup")
    }

    private func firstMatch(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(source.startIndex..., in: source)
        guard let match = regex.firstMatch(in: source, range: range), match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: source) else {
            return nil
        }
        return String(source[valueRange])
    }
}
