import Foundation
import Observation

@Observable
public class BookmarkStore {
    public static let shared = BookmarkStore()

    public var bookmarks: [Bookmark] = []
    private let saveURL: URL

    init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let supportDir = paths[0].appendingPathComponent("SwiftCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        self.saveURL = supportDir.appendingPathComponent("bookmarks.json")
        load()
    }

    public func add(fileName: String, lineNumber: Int, filePath: String) {
        let bookmark = Bookmark(fileName: fileName, lineNumber: lineNumber, filePath: filePath)
        bookmarks.append(bookmark)
        save()
    }

    public func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            try data.write(to: saveURL)
        } catch {
            print("Failed to save bookmarks: \(error)")
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: saveURL)
            bookmarks = try JSONDecoder().decode([Bookmark].self, from: data)
        } catch {
            bookmarks = []
        }
    }
}

public struct Bookmark: Identifiable, Codable {
    public let id: UUID
    public let fileName: String
    public let lineNumber: Int
    public let filePath: String

    public init(id: UUID = UUID(), fileName: String, lineNumber: Int, filePath: String) {
        self.id = id
        self.fileName = fileName
        self.lineNumber = lineNumber
        self.filePath = filePath
    }
}
