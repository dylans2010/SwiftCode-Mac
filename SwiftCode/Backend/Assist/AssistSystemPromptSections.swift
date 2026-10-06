import Foundation

/// Pure helpers for addressing `AgentSystemAsset.md` by top-level section.
///
/// The asset is currently delivered whole via `AssistManager.getSystemPrompt()`.
/// These helpers let future call sites extract only the sections relevant to a
/// task (e.g. the Tool Selection & Usage reference) without changing the
/// delivery pipeline. All functions are pure and safe to call from any thread.
public enum AssistSystemPromptSections {
    /// Returns the normalized titles of all top-level (`## `) sections in
    /// document order, e.g. `"TOOL SELECTION & USAGE"`.
    public static func sectionNames(in prompt: String) -> [String] {
        prompt
            .components(separatedBy: "\n")
            .compactMap { normalizeHeading($0) }
    }

    /// Extracts the full text of a top-level section, including its heading
    /// line, up to (but excluding) the next top-level heading.
    /// `name` may be the normalized title (`"TOOL SELECTION & USAGE"`) or the
    /// full heading line (`"## 5. TOOL SELECTION & USAGE"`).
    /// Returns `nil` when no matching section exists.
    public static func extractSection(named name: String, from prompt: String) -> String? {
        let wanted = normalizeHeading(name) ?? name.trimmingCharacters(in: .whitespaces)
        let lines = prompt.components(separatedBy: "\n")
        var start: Int?
        var end = lines.count
        for (index, line) in lines.enumerated() {
            guard let title = normalizeHeading(line) else { continue }
            if start == nil {
                if title == wanted {
                    start = index
                }
            } else {
                end = index
                break
            }
        }
        guard let startIndex = start else { return nil }
        return lines[startIndex..<end].joined(separator: "\n")
    }

    /// Normalizes a markdown heading line to its bare title, or returns `nil`
    /// when the line is not a top-level (`## `) section heading.
    /// `"## 5. TOOL SELECTION & USAGE"` -> `"TOOL SELECTION & USAGE"`.
    public static func normalizeHeading(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("## ") else { return nil }
        var title = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        // Strip a leading numeric prefix such as "5. ".
        if let dotRange = title.range(of: ". ") {
            let prefix = title[..<dotRange.lowerBound]
            if prefix.allSatisfy({ $0.isNumber }) {
                title = String(title[dotRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return title.isEmpty ? nil : title
    }
}
