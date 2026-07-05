import Foundation

struct ProjectFolder: Identifiable, Codable, Equatable, Hashable {
    var folderId: UUID
    var folderName: String
    var iconSymbol: String
    var colorHex: String
    var gradientColors: [String]?
    var createdDate: Date
    var projectIdentifiers: [UUID]

    var id: UUID { folderId }

    init(
        folderId: UUID = UUID(),
        folderName: String,
        iconSymbol: String = "folder.fill",
        colorHex: String = "#4F86FF",
        gradientColors: [String]? = nil,
        createdDate: Date = Date(),
        projectIdentifiers: [UUID] = []
    ) {
        self.folderId = folderId
        self.folderName = folderName
        self.iconSymbol = iconSymbol
        self.colorHex = colorHex
        self.gradientColors = gradientColors
        self.createdDate = createdDate
        self.projectIdentifiers = projectIdentifiers
    }
}
