import Foundation

public enum NewFileComment {
    public static let defaultTemplate = """
        //
        // {filename}
        // {projectname}
        //
        // Created by {username} on {date}.
        """

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
