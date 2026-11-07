import Testing
import Foundation
@testable import YcodeProject

@Suite("XCProjDocumentTests")
struct XCProjDocumentTests {
    @Test("Load and round-trip reference Testing.xcodeproj/project.xcproj")
    func testLoadReferenceXCProj() throws {
        let referencePath = "/Users/dylan/Downloads/Testing.xcodeproj/project.xcproj"
        guard FileManager.default.fileExists(atPath: referencePath) else {
            return
        }
        let url = URL(fileURLWithPath: referencePath)
        let doc = try XCProjDocument.load(from: url)

        #expect(doc.defaultConfiguration == "Release")
        #expect(doc.configurations.contains("Debug"))
        #expect(doc.configurations.contains("Release"))
        #expect(doc.localizations.development == "en")
        #expect(doc.targets.count >= 1)
        #expect(doc.targets.first?.name == "MyApp")
        #expect(doc.targets.first?.productType == "application")

        let encoded = try doc.encode()
        let reloaded = try XCProjDocument.decode(from: encoded)
        #expect(reloaded.defaultConfiguration == doc.defaultConfiguration)
        #expect(reloaded.targets.count == doc.targets.count)
    }

    @Test("Create from scratch and verify encode")
    func testCreateScratchXCProj() throws {
        let doc = XCProjDocument(
            defaultConfiguration: "Release",
            configurations: ["Debug", "Release"],
            targets: [
                XCProjDocument.Target(
                    name: "SampleApp",
                    id: "00000000000100000000",
                    product: "Products/SampleApp.app",
                    productType: "application"
                )
            ]
        )
        let data = try doc.encode()
        let decoded = try XCProjDocument.decode(from: data)
        #expect(decoded.targets.first?.name == "SampleApp")
    }
}
