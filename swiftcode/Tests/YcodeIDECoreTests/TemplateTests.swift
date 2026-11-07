import Foundation
import Testing
import YcodeBuild
import YcodeProject
@testable import YcodeIDECore

@MainActor
@Suite(.serialized, .heavyIntegration, .timeLimit(.minutes(5))) struct TemplateTests {
    @Test func fileTemplateContents() {
        #expect(FileTemplate.swiftClass.files(named: "Widget").map(\.0) == ["Widget.swift"])
        #expect(FileTemplate.objcClass.files(named: "Widget").map(\.0) == ["Widget.h", "Widget.m"])
        #expect(FileTemplate.propertyList.files(named: "Config")[0].1.contains("<dict/>"))
        #expect(FileTemplate.empty.files(named: "README").first?.1 == "")
    }

    @Test func scaffoldTemplatesRegistrationAndEngine() async throws {
        let templates = ProjectTemplateCatalog.scaffoldTemplates
        #expect(templates.count >= 38)

        let requiredNames = [
            "Command Line Tool",
            "Document App",
            "Framework",
            "Metal Game",
            "SpriteKit Game",
            "Multiplatform App",
            "Safari Extension",
            "Static Library",
            "Swift Macro",
            "Swift Package"
        ]

        for name in requiredNames {
            let found = ProjectTemplateCatalog.scaffoldTemplate(named: name)
            #expect(found != nil, "Missing template: \(name)")
            #expect(!(found?.files.isEmpty ?? true))
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("scaffold-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let cliTemplate = CommandLineToolTemplate()
        try await ProjectScaffoldTemplateEngine.shared.createProject(at: tempURL, template: cliTemplate)
        let mainSwift = tempURL.appendingPathComponent("main.swift")
        #expect(FileManager.default.fileExists(atPath: mainSwift.path))
    }
}
