import Foundation
import Testing
@testable import SwiftCodeIDECore

@Suite struct LicenseCatalogTests {
    private func fixtureDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LicenseCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "MIT License\n\nPermission is hereby granted.".write(to: dir.appendingPathComponent("MIT.txt"), atomically: true, encoding: .utf8)
        try "Apache License 2.0\n\nTerms and conditions.".write(to: dir.appendingPathComponent("Apache-2.0.txt"), atomically: true, encoding: .utf8)
        try "GPL-3.0 linking exception\n\nException text.".write(to: dir.appendingPathComponent("GPL-3.0-exception.txt"), atomically: true, encoding: .utf8)
        try "symbol list, not a license".write(to: dir.appendingPathComponent("sfsymbols.txt"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func loadsTxtFilesSkippingSFSymbols() throws {
        let dir = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let templates = LicenseCatalog.loadTemplates(directory: dir)
        #expect(templates.count == 3)
        #expect(templates.map(\.id).sorted() == ["Apache-2.0", "GPL-3.0-exception", "MIT"])
    }

    @Test func firstNonEmptyLineIsTheNameAndExceptionsAreCategorised() throws {
        let dir = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let templates = LicenseCatalog.loadTemplates(directory: dir)
        let mit = try #require(templates.first(where: { $0.id == "MIT" }))
        #expect(mit.name == "MIT License")
        #expect(mit.category == "SPDX")
        #expect(mit.summary.contains("MIT License"))
        #expect(mit.body.contains("Permission is hereby granted."))
        let exception = try #require(templates.first(where: { $0.id == "GPL-3.0-exception" }))
        #expect(exception.category == "Exception")
    }

    @Test func templatesAreSortedByName() throws {
        let dir = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let templates = LicenseCatalog.loadTemplates(directory: dir)
        #expect(templates.map(\.name) == ["Apache License 2.0", "GPL-3.0 linking exception", "MIT License"])
    }

    @Test func emptyDirectoryLoadsNothing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LicenseCatalogTests-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(LicenseCatalog.loadTemplates(directory: dir).isEmpty)
    }
}
