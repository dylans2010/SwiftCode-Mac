import Foundation

public struct PreviewSimulationEntry: Sendable {
    public let appName: String
    public let rootViewType: String
    public let sceneType: String
}

public final class PreviewEntryResolver: Sendable {
    public init() {}

    public func resolve(projectStructure: PreviewProjectStructure, preferredView: String?) throws -> PreviewSimulationEntry {
        if let preferredView {
            return PreviewSimulationEntry(appName: "View Preview", rootViewType: preferredView, sceneType: "WindowGroup")
        }

        if let entryFile = projectStructure.appEntryPoint {
            if let source = try? String(contentsOf: entryFile, encoding: .utf8) {
                let appName = firstMatch(in: source, pattern: #"@main\s+struct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*App"#) ?? "SimulationApp"
                if let rootView = firstMatch(in: source, pattern: #"WindowGroup\s*\{[\s\S]*?([A-Za-z_][A-Za-z0-9_]*)\s*\("#) {
                    return PreviewSimulationEntry(appName: appName, rootViewType: rootView, sceneType: "WindowGroup")
                }
            }
        }

        if let firstView = projectStructure.swiftUIViewTypes.first {
            return PreviewSimulationEntry(appName: "View Preview", rootViewType: firstView, sceneType: "WindowGroup")
        }

        return PreviewSimulationEntry(appName: "View Preview", rootViewType: "ContentView", sceneType: "WindowGroup")
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
