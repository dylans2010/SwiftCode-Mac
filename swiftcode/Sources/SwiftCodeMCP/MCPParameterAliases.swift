import Foundation
import SwiftCodeAssistant

/// Legacy parameter-name aliases, applied before argument validation.
///
/// Behaviour source: Legacy's `AssistToolRegistry.validate`
/// (Dylan's own code, ported under MIT), which normalises arguments
/// before its required/type checks:
///
/// * `path` ← `filePath` / `file_path` / `targetFile` / `file`
/// * `content` ← `fileContent` / `file_content` / `code` / `data`
/// * `target` ← `targetContent` / `old_string` / `old_str` / `find`
/// * `replacement` ← `replacementContent` / `new_string` / `new_str` / `replace`
/// * `command` ← `cmd`
/// * `source` ← `sourcePath` (Legacy `file_copy` / `file_move`)
/// * `destination` ← `destinationPath` (Legacy `file_copy` / `file_move`)
/// * `newName` ← `newPath` (Legacy `file_rename` passes a path)
///
/// Plus one per-tool Legacy alias verified live:
/// `AssistDataMutationTools` reads `input["path"] ?? input["csvPath"]`,
/// so `csvPath` is also a `path` alias (for `csv_to_json`).
///
/// Waves 1–6 left aliases unimplemented because SwiftCode's
/// `MCPTool.argumentProblem` rejects unknown arguments first
/// (`additionalProperties: false`): an aliased call failed with
/// "unknown argument" before the handler ever ran, and an alias
/// could not satisfy the `required` list. The fix is normalisation
/// at the `MCPServer.run` funnel (coordinator-owned patch): rewrite
/// the arguments with this table, then validate the rewritten set.
///
/// Rules (Legacy's, plus the one SwiftCode needs):
///
/// * An alias only fills its canonical name when the canonical is
///   absent — a caller that passes both keeps the canonical value
///   (Legacy ignores the alias then, and so does this: the alias
///   key is dropped either way, so it can never trip the unknown-
///   argument rejection for having supplied a redundant name).
/// * An alias key is only consumed (removed) when it is NOT itself a
///   declared property of the tool being called. `code` is the
///   canonical parameter of `code_insert`, `data` of
///   `ai_context_memory`, so those must never be swallowed as
///   aliases for `content`. `declaredProperties` is the tool's input
///   schema property set.
/// * An alias that is a declared property keeps its own meaning and
///   is left untouched — the tool's own parameter wins over the
///   alias table.
public enum MCPParameterAliases {
    /// (canonical, aliases) in Legacy's order; the first alias
    /// present wins when several are given.
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

    /// Aliases for one canonical name, or [] when it has none.
    public static func aliases(for canonical: String) -> [String] {
        table.first { $0.canonical == canonical }?.aliases ?? []
    }

    /// The canonical name an argument key is an alias for, if any.
    public static func canonical(for key: String) -> String? {
        table.first { $0.aliases.contains(key) }?.canonical
    }

    /// Rewrites `args` with the alias table. `declaredProperties` is
    /// the called tool's input-schema property names: alias keys that
    /// are declared properties are left untouched.
    public static func normalized(_ args: [String: AnyJSON], declaredProperties: Set<String>) -> [String: AnyJSON] {
        var result = args
        for (canonical, aliases) in table {
            let canonicalMissing = result[canonical] == nil || result[canonical] == .null
            for alias in aliases where !declaredProperties.contains(alias) {
                guard let value = result[alias] else { continue }
                // A null alias carries no value: drop it rather than
                // letting it trip the unknown-argument rejection.
                if value == .null { result.removeValue(forKey: alias); continue }
                if canonicalMissing { result[canonical] = value }
                result.removeValue(forKey: alias)
                break
            }
        }
        return result
    }
}
