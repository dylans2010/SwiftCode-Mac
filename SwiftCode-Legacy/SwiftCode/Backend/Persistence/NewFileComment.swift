import Foundation

public struct NewFileComment {
    public static func generateHeader(filename: String, projectName: String) async -> String {
        let userName = await PreferencesStore.shared.get(forKey: "user_name") as? String ?? "User"
        let customTemplate = await PreferencesStore.shared.get(forKey: "file_header_template") as? String

        if let template = customTemplate, !template.isEmpty {
            return template
                .replacingOccurrences(of: "{filename}", with: filename)
                .replacingOccurrences(of: "{projectname}", with: projectName)
                .replacingOccurrences(of: "{username}", with: userName)
                .replacingOccurrences(of: "{date}", with: formatDate(Date()))
        }

        let dateString = formatDate(Date())

        return """
        //
        //  \(filename)
        //  \(projectName)
        //
        //  Created by \(userName) on \(dateString).
        //

        """
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yy"
        return formatter.string(from: date)
    }
}
