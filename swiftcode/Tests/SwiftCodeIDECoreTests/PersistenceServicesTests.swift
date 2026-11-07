import Foundation
import Testing
@testable import SwiftCodeIDECore

@Suite("Persistence-Services ports", .serialized)
struct PersistenceServicesTests {

    @Test("UnifiedLogger logs and filters by subsystem")
    @MainActor
    func unifiedLoggerFilters() {
        let logger = UnifiedLogger.shared
        logger.log("persistence-test-message", severity: .info, subsystem: "PersistenceTest", operation: "Test")
        let found = logger.filteredLogs(query: "persistence-test-message", subsystem: "PersistenceTest")
        #expect(found.count >= 1)
        #expect(found.allSatisfy { $0.subsystem == "PersistenceTest" })
        logger.clear()
        #expect(logger.logs.count == 1)
        logger.clear()
    }

    @Test("UnifiedLogger export format")
    @MainActor
    func unifiedLoggerExportFormat() {
        let logger = UnifiedLogger.shared
        logger.clear()
        logger.log("hello", severity: .warning, subsystem: "S", operation: "Op")
        let text = logger.formatLogsForExport()
        #expect(text.contains("[WARNING]"))
        #expect(text.contains("[S]"))
        #expect(text.contains("hello"))
        logger.clear()
    }

    @Test("FolderManager create/rename/addProject/projects/delete")
    @MainActor
    func folderManagerRoundTrip() {
        let manager = FolderManager.shared
        let name = "TestFolder-\(UUID().uuidString)"
        manager.createFolder(name: name, symbol: "folder.fill", colorHex: "#4F86FF")
        guard let folder = manager.folders.first(where: { $0.folderName == name }) else {
            Issue.record("folder was not created")
            return
        }
        let projectID = UUID()
        manager.addProject(projectID, to: folder.folderId)
        guard let updated = manager.folders.first(where: { $0.folderId == folder.folderId }) else {
            Issue.record("folder disappeared after addProject")
            return
        }
        struct FakeProject: Identifiable { let id: UUID }
        let found = manager.projects(in: updated, allProjects: [FakeProject(id: projectID), FakeProject(id: UUID())])
        #expect(found.count == 1)
        #expect(found[0].id == projectID)
        manager.renameFolder(updated, to: name + "-renamed")
        #expect(manager.folders.contains(where: { $0.folderName == name + "-renamed" }))
        manager.deleteFolder(folder)
        #expect(!manager.folders.contains(where: { $0.folderId == folder.folderId }))
    }

    @Test("ProjectRegistryStore save/load round-trips")
    func registryStoreRoundTrip() async throws {
        let store = ProjectRegistryStore.shared
        let before = try await store.load()
        let entry = ProjectRegistryEntry(name: "TestProject-\(UUID().uuidString)",
                                         rootURL: URL(fileURLWithPath: "/tmp"),
                                         kind: .folder)
        try await store.save(before + [entry])
        let loaded = try await store.load()
        #expect(loaded.contains(where: { $0.id == entry.id }))
        try await store.save(before)
        #expect(try await store.load().count == before.count)
    }

    @Test("ThemeStore save/load round-trips a built-in theme")
    func themeStoreRoundTrip() async throws {
        let store = ThemeStore.shared
        let theme = EditorTheme.builtIns[1]
        try await store.saveTheme(theme)
        let loaded = try await store.loadThemes()
        #expect(loaded.contains(where: { $0.name == theme.name && $0.background == theme.background }))
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Themes", isDirectory: true)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(theme.fileName))
    }

    @Test("ProjectZipImporter export/import round-trips a directory")
    func zipRoundTrip() async throws {
        let fm = FileManager.default
        #if os(macOS)
        try #require(fm.isExecutableFile(atPath: "/usr/bin/ditto"), "ditto is required for zip tests")
        #else
        try #require(fm.isExecutableFile(atPath: "/usr/bin/zip") && fm.isExecutableFile(atPath: "/usr/bin/unzip"),
                      "zip/unzip are required for zip tests")
        #endif
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let source = base.appendingPathComponent("MyApp", isDirectory: true)
        try fm.createDirectory(at: source.appendingPathComponent("Sources", isDirectory: true), withIntermediateDirectories: true)
        try "hello".write(to: source.appendingPathComponent("Sources/main.swift"), atomically: true, encoding: .utf8)

        let zipURL = try await ProjectZipImporter.shared.exportZip(projectURL: source, projectName: "MyApp")
        #expect(fm.fileExists(atPath: zipURL.path))

        let imported = try await ProjectZipImporter.shared.importZip(at: zipURL, into: base)
        #expect(imported.name == "MyApp")
        let roundTripped = try String(contentsOf: imported.directoryURL.appendingPathComponent("Sources/main.swift"), encoding: .utf8)
        #expect(roundTripped == "hello")
    }

    @Test("Every ported Legacy template has a name, icon and files")
    func legacyTemplatesAreComplete() {
        let templates: [any ProjectScaffoldTemplate] = [
            AnalyticsDashboardViewTemplate(), AudioPlayerViewTemplate(),
            BudgetTrackerViewTemplate(), CalculatorViewTemplate(),
            CalendarViewTemplate(), ChatViewTemplate(),
            DashboardViewTemplate(), DrawingViewTemplate(),
            ECommerceViewTemplate(), FileBrowserViewTemplate(),
            FitnessTrackerViewTemplate(), IntroductionTemplate(),
            LoginViewTemplate(), MapViewTemplate(),
            MarkdownEditorViewTemplate(), NewsReaderViewTemplate(),
            NotesViewTemplate(), OnboardingViewTemplate(),
            PhotoGalleryViewTemplate(), ProfileViewTemplate(),
            QuizViewTemplate(), RecipeViewTemplate(),
            SettingsViewTemplate(), TaskBoardViewTemplate(),
            TodoViewTemplate(), WeatherViewTemplate(),
            MenuBarAppTemplate(), SystemExtensionTemplate(),
        ]
        #expect(templates.count == 28)
        for template in templates {
            #expect(!template.name.isEmpty, "empty name for \(type(of: template))")
            #expect(!template.icon.isEmpty, "empty icon for \(type(of: template))")
            #expect(!template.files.isEmpty, "no files for \(type(of: template))")
            #expect(template.files.allSatisfy { !$0.path.isEmpty && !$0.content.isEmpty })
        }
    }

    @Test("ProjectScaffoldTemplateEngine creates a template's files, including nested paths")
    func templateEngineCreatesFiles() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        try await ProjectScaffoldTemplateEngine.shared.createProject(at: dir, template: IntroductionTemplate())
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("Welcome.swift").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("Features/EditorTips.swift").path))
        let welcome = try String(contentsOf: dir.appendingPathComponent("Welcome.swift"), encoding: .utf8)
        #expect(welcome.contains("WelcomeView"))
    }

    @Test("LegacyProjectTemplateManager applies a template into a directory")
    @MainActor
    func templateManagerApplies() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        let manager = LegacyProjectTemplateManager.shared
        guard let template = manager.templates.first(where: { $0.id == "swiftui_app" }) else {
            Issue.record("swiftui_app template missing")
            return
        }
        try manager.applyTemplate(template, projectName: "HelloApp", to: dir)
        let appEntry = dir.appendingPathComponent("Sources/AppEntry.swift")
        #expect(fm.fileExists(atPath: appEntry.path))
        #expect(try String(contentsOf: appEntry, encoding: .utf8).contains("HelloAppApp"))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("Sources/Views/ContentView.swift").path))
    }

    @Test("LegacyProjectTemplateManager template ids are unique")
    @MainActor
    func templateManagerIdsUnique() {
        let ids = LegacyProjectTemplateManager.shared.templates.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.count == 17)
    }
}
