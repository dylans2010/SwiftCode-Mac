import Foundation
import Observation

@Observable
@MainActor
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

    public func add(fileName: String, lineNumber: Int, filePath: String, title: String? = nil, url: String? = nil, folder: String? = nil, icon: String? = nil, notes: String? = nil) {
        let bookmark = Bookmark(
            id: UUID(),
            fileName: fileName,
            lineNumber: lineNumber,
            filePath: filePath,
            title: title,
            url: url,
            folder: folder,
            icon: icon,
            notes: notes
        )
        bookmarks.append(bookmark)
        save()
    }

    public func addBookmark(_ bookmark: Bookmark) {
        bookmarks.append(bookmark)
        save()
    }

    public func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    public func duplicate(_ bookmark: Bookmark) {
        let dup = Bookmark(
            id: UUID(),
            fileName: bookmark.fileName,
            lineNumber: bookmark.lineNumber,
            filePath: bookmark.filePath,
            title: bookmark.title != nil ? "\(bookmark.title!) Copy" : nil,
            url: bookmark.url,
            folder: bookmark.folder,
            icon: bookmark.icon,
            notes: bookmark.notes
        )
        bookmarks.append(dup)
        save()
    }

    public func update(_ bookmark: Bookmark) {
        if let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[idx] = bookmark
            save()
        }
    }

    public func reorder(fromOffsets indices: IndexSet, toOffset newOffset: Int) {
        bookmarks.move(fromOffsets: indices, toOffset: newOffset)
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

public struct Bookmark: Identifiable, Codable, Hashable {
    public var id: UUID
    public var fileName: String
    public var lineNumber: Int
    public var filePath: String
    public var title: String?
    public var url: String?
    public var folder: String?
    public var icon: String?
    public var notes: String?

    public init(id: UUID = UUID(), fileName: String, lineNumber: Int, filePath: String, title: String? = nil, url: String? = nil, folder: String? = nil, icon: String? = nil, notes: String? = nil) {
        self.id = id
        self.fileName = fileName
        self.lineNumber = lineNumber
        self.filePath = filePath
        self.title = title
        self.url = url
        self.folder = folder
        self.icon = icon
        self.notes = notes
    }
}
