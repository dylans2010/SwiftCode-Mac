// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Services/FolderManager.swift
// Adapted for SwiftCode: FolderManager + ProjectFolder (Legacy defined ProjectFolder in Models/ProjectFolder.swift; declared here verbatim so the file is self-contained). ObservableObject -> @Observable; projects(in:allProjects:) is generic over any Identifiable project with a UUID id, so it no longer depends on Legacy's Project model.

import Foundation
import Observation

/// A user-created folder grouping projects in the library. Shape matches
/// Legacy's `Models/ProjectFolder.swift` exactly, so folders persisted by
/// Legacy still decode.
///
/// COORDINATOR NOTE — same name, different type: `SwiftCodeIDEShell` also
/// defines a public `ProjectFolder` (`ProjectDashboardModel.swift`) with a
/// different shape (id/name/projectPaths/createdAt, stored in
/// `SwiftCode/ProjectDashboard/folders.json`). Swift prefers the current
/// module's own declaration, so this does not break the build, but the two
/// must not be confused: this one is Legacy's library-folder model
/// (UserDefaults `com.swiftcode.projectFolders`); that one is the dashboard
/// folder model. If the coordinator wants a single type, rename one of them.
public struct ProjectFolder: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var folderId: UUID
    public var folderName: String
    public var iconSymbol: String
    public var colorHex: String
    public var gradientColors: [String]?
    public var createdDate: Date
    public var projectIdentifiers: [UUID]

    public var id: UUID { folderId }

    public init(
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

/// Organises library projects into user-created folders, persisted in
/// UserDefaults under `com.swiftcode.projectFolders`.
@Observable
@MainActor
public final class FolderManager: Sendable {
    public static let shared = FolderManager()

    public var folders: [ProjectFolder] = [] {
        didSet { persistFolders() }
    }

    private static let foldersKey = "com.swiftcode.projectFolders"

    private init() {
        loadFolders()
    }

    public func createFolder(name: String, symbol: String, colorHex: String, gradientColors: [String]? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let folder = ProjectFolder(folderName: trimmed, iconSymbol: symbol, colorHex: colorHex, gradientColors: gradientColors)
        folders.append(folder)
    }

    public func renameFolder(_ folder: ProjectFolder, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = folders.firstIndex(where: { $0.folderId == folder.folderId }) {
            folders[index].folderName = trimmed
        }
    }

    public func deleteFolder(at offsets: IndexSet) {
        folders.remove(atOffsets: offsets)
    }

    public func deleteFolder(_ folder: ProjectFolder) {
        folders.removeAll { $0.folderId == folder.folderId }
    }

    public func addProject(_ projectId: UUID, to folderId: UUID) {
        guard let index = folders.firstIndex(where: { $0.folderId == folderId }) else { return }
        if !folders[index].projectIdentifiers.contains(projectId) {
            folders[index].projectIdentifiers.append(projectId)
        }
    }

    /// The projects in `folder`, from any list of identifiable projects
    /// (Legacy took `[Project]`; SwiftCode's library items are not Legacy
    /// projects, so the filter is generic over the id only).
    public func projects<P: Identifiable>(in folder: ProjectFolder, allProjects: [P]) -> [P] where P.ID == UUID {
        allProjects.filter { folder.projectIdentifiers.contains($0.id) }
    }

    private func persistFolders() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(folders) {
            UserDefaults.standard.set(data, forKey: Self.foldersKey)
        }
    }

    private func loadFolders() {
        guard let data = UserDefaults.standard.data(forKey: Self.foldersKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        folders = (try? decoder.decode([ProjectFolder].self, from: data)) ?? []
    }
}
