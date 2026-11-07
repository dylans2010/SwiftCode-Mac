import Foundation
import Testing
@testable import SwiftCodeProject

@Suite struct SkillsBundleTests {
    @Test func validatesValidSkillsBundle() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = try SkillsBundleTemplate.createBundle(
            at: tempDir,
            bundleName: "TestSkills.skillsbundle",
            initialSkillName: "calendar-lookup"
        )

        let validator = SkillsBundleValidator()
        let diagnostics = validator.validate(bundleURL: bundleURL)
        #expect(diagnostics.isEmpty)
    }

    @Test func flagsInvalidSkillFolderName() {
        #expect(SkillsBundleValidator.isValidSkillFolderName("valid-name-123"))
        #expect(!SkillsBundleValidator.isValidSkillFolderName("Invalid_Name!"))
        #expect(!SkillsBundleValidator.isValidSkillFolderName("UppercaseName"))
    }

    @Test func flagsUnknownFrontMatterFields() {
        let content = """
        ---
        name: test-skill
        description: A test skill
        version: 1.0.0
        ---

        Body instructions.
        """
        let validator = SkillsBundleValidator()
        let diags = validator.validateSkillContent(content)
        #expect(diags.contains(where: { $0.message.contains("Unknown front-matter field 'version'") }))
    }

    @Test func flagsExcessiveBodyLength() {
        let longBody = String(repeating: "a", count: 10001)
        let content = """
        ---
        name: test-skill
        description: A test skill
        ---

        \(longBody)
        """
        let validator = SkillsBundleValidator()
        let diags = validator.validateSkillContent(content)
        #expect(diags.contains(where: { $0.message.contains("exceeds maximum allowed") }))
    }
}
