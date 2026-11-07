import Foundation

extension MetaAssistProvider {
    public static let shared = MetaAssistProvider()

    public func discoverModels() async -> [MetaModelItem] {
        await fetchModels()
    }

    public static func normalizeToolName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["muse.", "muse_", "assist.", "assist_"] where name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        name = name
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        return name
    }
}
