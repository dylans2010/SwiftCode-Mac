import Foundation

/// The new-file header comment — Legacy's
/// `Backend/Persistence/NewFileComment.swift`, ported.
///
/// No equivalent existed in the destination: nothing generated
/// the `// Created by … on …` header for new files. The generator
/// is a pure function (explicit parameters, no global reads), so
/// it is testable and the call sites — the new-file template
/// flow — pass the values in. The template placeholders are
/// Legacy's: `{filename}`, `{projectname}`, `{username}`, `{date}`.
/// The date renders as `M/d/yy`, as Legacy did.

public enum NewFileComment {
    /// Legacy's default header, with placeholders.
    public static let defaultTemplate = """
        //
        // {filename}
        // {projectname}
        //
        // Created by {username} on {date}.
        """

    /// Renders a header from a template. Unknown placeholders are
    /// left as-is rather than silently dropped, so a typo in a
    /// custom template is visible in the file it produces.
    public static func generateHeader(filename: String, projectName: String,
                                      userName: String, customTemplate: String? = nil,
                                      date: Date = Date()) -> String {
        let template = customTemplate ?? defaultTemplate
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d/yy"
        return template
            .replacingOccurrences(of: "{filename}", with: filename)
            .replacingOccurrences(of: "{projectname}", with: projectName)
            .replacingOccurrences(of: "{username}", with: userName)
            .replacingOccurrences(of: "{date}", with: formatter.string(from: date))
    }
}
