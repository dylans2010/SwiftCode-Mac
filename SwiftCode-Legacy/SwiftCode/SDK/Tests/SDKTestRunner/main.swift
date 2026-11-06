import Foundation
import SwiftCodeSDK

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: String = #file, line: Int = #line) {
    if a != b {
        print("❌ FAIL: \(message) ('\(a)' != '\(b)') at \(file):\(line)")
        exit(1)
    }
}

func assertTrue(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if !condition {
        print("❌ FAIL: \(message) (condition is false) at \(file):\(line)")
        exit(1)
    }
}

print("Running SwiftCode SDK Test Suite...")

// Test 1: SDK Version
print("  - Running testSDKVersion...")
assertEqual(SDKVersion.current.major, 1, "Major version should be 1")
assertEqual(SDKVersion.current.minor, 0, "Minor version should be 0")
assertTrue(SDKVersion.current.isCompatibleWithHost, "Should be compatible with host")

// Test 2: Diagnostics Engine
print("  - Running testDiagnostics...")
let engine = DiagnosticEngine()
engine.emit(code: .projectInvalidIdentifier, severity: .error, message: "Invalid ID")
assertTrue(engine.hasErrors, "Engine should report errors")
assertEqual(engine.errorCount, 1, "Error count should be 1")
let formatted = DiagnosticFormatter.formatText(engine.allDiagnostics)
assertTrue(formatted.contains("SC-P004"), "Formatted text should contain SC-P004")

// Test 3: Workspace Path Traversal
print("  - Running testWorkspacePathTraversal...")
let currentSDKRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .path
let root = WorkspacePath(currentSDKRoot)
let safe = WorkspacePath("\(currentSDKRoot)/Sources")
let malicious = WorkspacePath("\(currentSDKRoot)/../../etc/passwd")
assertTrue(safe.isWithin(root: root), "Safe path should be within root")
assertTrue(!malicious.isWithin(root: root), "Malicious traversal should NOT be within root")

// Test 4: Extension Validation
print("  - Running testExtensionValidation...")
let validator = ExtensionValidator()
let invalidManifest = ExtensionManifest(
    manifestVersion: 2,
    id: "",
    name: "Test Ext",
    version: "invalid-version",
    type: "extension"
)
let diags = validator.validate(manifest: invalidManifest)
assertTrue(diags.contains { $0.code == .manifestInvalidVersion }, "Should flag invalid manifestVersion")
assertTrue(diags.contains { $0.code == .manifestMissingRequiredField }, "Should flag missing required field")

// Test 5: Canonical Capabilities Recognition
print("  - Running testCanonicalCapabilities...")
let canonicalCaps = [
    "project.read", "workspace.read", "workspace.write",
    "source-control.read", "source-control.write",
    "build.execute", "task.execute", "network.request",
    "ui.contribute", "credentials.use", "use.Security",
    "assist.invoke", "assist.ui", "assist.headless",
    "db.ExploreView", "ci.VisualWF", "virtualization.view",
    "deployConsole.view", "use.SwiftCodeModel", "terminal.sandbox",
    "simulator.view", "preview.live", "uibuilder.open",
    "symbols.browse", "docs.search", "dictionary.open",
    "deviceconnect.open", "security.addValue", "security.hasValue",
    "security.listValueIDs", "security.deleteValue", "security.useValue"
]
for capID in canonicalCaps {
    assertTrue(ExtensionCapabilityID(rawValue: capID) != nil, "Should recognize canonical capability \(capID)")
}

// Test 6: Toolchain Discovery
print("  - Running testToolchainDiscovery...")
let toolchain = Toolchain()
let gitPath = toolchain.resolveExecutable(name: "git")
assertTrue(gitPath != nil, "Git executable should be discovered")

// Test 7: Project Inspector
print("  - Running testProjectInspector...")
let inspector = ProjectInspector()
let metadata = try inspector.inspect(at: currentSDKRoot)
assertEqual(metadata.type, .swiftPackage, "SDK should be identified as a Swift package")

print("✅ All 7 SwiftCode SDK test suites PASSED successfully!")
exit(0)
