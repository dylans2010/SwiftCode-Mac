import Foundation
import Observation

@Observable
@MainActor
public class BreakpointStore {
    public static let shared = BreakpointStore()

    public var breakpoints: [Breakpoint] = []
    private let saveURL: URL

    init() {
        let supportDir = CodingManager.appSupportRoot
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        self.saveURL = supportDir.appendingPathComponent("breakpoints.json")
        load()
    }

    public func add(fileName: String, lineNumber: Int, filePath: String) {
        let bp = Breakpoint(fileName: fileName, lineNumber: lineNumber, filePath: filePath, isEnabled: true)
        breakpoints.append(bp)
        save()
    }

    public func toggle(id: UUID) {
        if let index = breakpoints.firstIndex(where: { $0.id == id }) {
            let bp = breakpoints[index]
            breakpoints[index] = Breakpoint(id: bp.id, fileName: bp.fileName, lineNumber: bp.lineNumber, filePath: bp.filePath, isEnabled: !bp.isEnabled)
            save()
        }
    }

    public func remove(id: UUID) {
        breakpoints.removeAll { $0.id == id }
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(breakpoints)
            try data.write(to: saveURL)
        } catch {
            print("Failed to save breakpoints: \(error)")
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: saveURL)
            breakpoints = try JSONDecoder().decode([Breakpoint].self, from: data)
        } catch {
            breakpoints = []
        }
    }
}

public struct Breakpoint: Identifiable, Codable {
    public let id: UUID
    public let fileName: String
    public let lineNumber: Int
    public let filePath: String
    public var isEnabled: Bool

    public init(id: UUID = UUID(), fileName: String, lineNumber: Int, filePath: String, isEnabled: Bool) {
        self.id = id
        self.fileName = fileName
        self.lineNumber = lineNumber
        self.filePath = filePath
        self.isEnabled = isEnabled
    }
}
