import Foundation

public struct SwiftLanguageProvider: LanguageProvider {
    public let id = "swift"
    public let displayName = "Swift"
    public let fileExtensions = ["swift"]
    public let iconName = "swift"
    public let iconColorName = "orange"
    public let capabilities: Set<LanguageCapability> = [.build, .run, .format, .lint, .autocomplete, .diagnostics]

    public let commentSyntax = CommentSyntax(linePrefix: "//", blockStart: "/*", blockEnd: "*/")

    public init() {}

    public func tokenize(line: String) -> [TokenizedLine.Token] {
        return SwiftTokenizer.shared.tokenize(line)
    }

    public func generateDefaultContent(fileName: String) -> String {
        let author = AppSettings.shared.fileHeaderAuthor
        let date = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)

        return """
//
//  \(fileName)
//
//  Created by \(author.isEmpty ? "User" : author) on \(date).
//

import Foundation

struct \(fileName.replacingOccurrences(of: ".swift", with: "")) {
    // TODO: Implement
}
"""
    }
}
