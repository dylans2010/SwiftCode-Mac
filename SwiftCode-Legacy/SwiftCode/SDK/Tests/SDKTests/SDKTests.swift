import Testing
@testable import SwiftCodeSDK

@Suite struct SDKTestSuite {
    @Test func sdkVersion() {
        #expect(SDKVersion.current.major == 1)
        #expect(SDKVersion.current.minor == 0)
        #expect(SDKVersion.current.isCompatibleWithHost)
    }

    @Test func diagnostics() {
        let engine = DiagnosticEngine()
        engine.emit(code: .projectInvalidIdentifier, severity: .error, message: "Invalid ID")
        #expect(engine.hasErrors)
        #expect(engine.errorCount == 1)
        let formatted = DiagnosticFormatter.formatText(engine.allDiagnostics)
        #expect(formatted.contains("SC-P004"))
    }

    @Test func workspacePathTraversal() {
        let root = WorkspacePath("/Users/dylan/SwiftCode-Mac/SwiftCode/SDK")
        let safe = WorkspacePath("/Users/dylan/SwiftCode-Mac/SwiftCode/SDK/Sources")
        let malicious = WorkspacePath("/Users/dylan/SwiftCode-Mac/SwiftCode/SDK/../../etc/passwd")

        #expect(safe.isWithin(root: root))
        #expect(!malicious.isWithin(root: root))
    }

    @Test func extensionValidation() {
        let validator = ExtensionValidator()
        let invalidManifest = ExtensionManifest(
            manifestVersion: 2,
            id: "",
            name: "Test Ext",
            version: "invalid-version",
            type: "extension"
        )
        let diags = validator.validate(manifest: invalidManifest)
        #expect(diags.contains { $0.code == .manifestInvalidVersion })
        #expect(diags.contains { $0.code == .manifestMissingRequiredField })
    }

    @Test func toolchainDiscovery() {
        let toolchain = Toolchain()
        let gitPath = toolchain.resolveExecutable(name: "git")
        #expect(gitPath != nil)
    }
}
