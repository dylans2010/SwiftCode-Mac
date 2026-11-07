import Foundation
import Testing
@testable import SwiftCodeMCP

@Suite struct LegacyReverseGapTests {

    @Test func reverseAllowListHasElevenOperationsAndNoForbiddenSurface() {
        let raw = EnginesReverseOperation.allCases.map(\.rawValue)
        #expect(raw.count == 11)
        #expect(raw == [
            "inspect_artifact", "inspect_macho", "inspect_plist",
            "inspect_signature", "list_architectures", "demangle_swift",
            "inspect_go_binary", "inspect_managed_artifact",
            "inspect_managed_members", "inspect_sqlite_database",
            "inspect_with_objdump",
        ])
        let forbidden = [
            "execute", "frida", "gdb", "ida", "jeb", "jadx", "adb",
            "firmware", "instrument", "mcp", "rizin",
        ]
        for item in forbidden {
            #expect(!raw.contains(where: { $0.contains(item) }),
                    "allow-list must not contain '\(item)'")
        }
    }

    @Test func reverseObjdumpSubOperations() {
        let raw = EnginesReverseObjdumpOperation.allCases.map(\.rawValue)
        #expect(raw == [
            "file_headers", "section_headers", "symbols", "relocations",
            "dwarf", "disassemble", "disassemble_all",
        ])
    }

    @Test func reverseTargetValidatorRejectsSystemTraversalRelativeAndMissing() {
        let root = URL(fileURLWithPath: "/tmp")
        expectFailure(EnginesReverseValidator.validateTarget(
            path: "/System/Library/Fonts/x", workspaceRoot: root),
                      "/System target must be rejected")
        expectFailure(EnginesReverseValidator.validateTarget(
            path: "/tmp/../etc/passwd", workspaceRoot: root),
                      "'..' target must be rejected")
        expectFailure(EnginesReverseValidator.validateTarget(
            path: "relative/path", workspaceRoot: root),
                      "relative target must be rejected")
        expectFailure(EnginesReverseValidator.validateTarget(
            path: nil, workspaceRoot: root),
                      "missing target must be rejected")
    }

    @Test func reverseTargetValidatorAcceptsInScopeFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("reverse-gap-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("sample")
        try Data([0x7F, 0x45, 0x4C, 0x46]).write(to: file)
        let result = EnginesReverseValidator.validateTarget(path: file.path, workspaceRoot: dir)
        guard case .success(let resolved) = result else {
            Issue.record("in-scope file must validate")
            return
        }
        #expect(resolved == file.resolvingSymlinksInPath().path)
    }

    @Test func reverseDisclaimerRefusesDRMAndLicenseTasks() {
        #expect(EnginesReverseValidator.refusalMessage(forTask: "bypass DRM on this game") != nil)
        #expect(EnginesReverseValidator.refusalMessage(
            forTask: "find how to circumvent the license check") != nil)
        #expect(EnginesReverseValidator.refusalMessage(
            forTask: "inspect how this authorized binary loads its config") == nil)
    }

    private func expectFailure(_ result: Result<String, ReverseValidationError>, _ message: String) {
        if case .success = result {
            Issue.record(Comment(rawValue: message))
        }
    }
}
