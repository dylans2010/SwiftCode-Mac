import Foundation
import SwiftCodeAssistant

public enum MCPParameterAliases {
    public static let table: [(canonical: String, aliases: [String])] = [
        ("path", ["filePath", "file_path", "targetFile", "file", "csvPath"]),
        ("content", ["fileContent", "file_content", "code", "data"]),
        ("target", ["targetContent", "old_string", "old_str", "find"]),
        ("replacement", ["replacementContent", "new_string", "new_str", "replace"]),
        ("command", ["cmd"]),
        ("source", ["sourcePath"]),
        ("destination", ["destinationPath"]),
        ("newName", ["newPath"]),
    ]

    public static func aliases(for canonical: String) -> [String] {
        table.first { $0.canonical == canonical }?.aliases ?? []
    }

    public static func canonical(for key: String) -> String? {
        table.first { $0.aliases.contains(key) }?.canonical
    }

    public static func normalized(_ args: [String: AnyJSON], declaredProperties: Set<String>) -> [String: AnyJSON] {
        var result = args
        for (canonical, aliases) in table {
            let canonicalMissing = result[canonical] == nil || result[canonical] == .null
            for alias in aliases where !declaredProperties.contains(alias) {
                guard let value = result[alias] else { continue }
                if value == .null { result.removeValue(forKey: alias); continue }
                if canonicalMissing { result[canonical] = value }
                result.removeValue(forKey: alias)
                break
            }
        }
        return result
    }
}
