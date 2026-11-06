import Foundation
import Testing
@testable import YcodeMCP

// MARK: - Legacy Reverse gap tests (Wave 18)
//
// Ported from Legacy
// `SwiftCode/Backend/Assist/API/Internal API/Reverse/ReverseTests.swift`
// (Dylan's own code; direct port authorised under MIT), adapted to the
// Ycode shape: Legacy's Reverse subsystem lives in Ycode as the
// `reverse_analyze` MCP tool (`YcodeTools+Engines.swift` /
// `YcodeTools+EnginesSupport.swift`: `EnginesReverseOperation`,
// `EnginesReverseObjdumpOperation`, `EnginesReverseValidator`).
//
// What is ported here — the checks `YcodeEnginesToolsTests` does NOT
// already cover at the tool level:
//   - the allow-list itself (exactly 11 operations, no forbidden
//     execution surface);
//   - the objdump sub-operation list;
//   - the target validator called directly (system path, traversal,
//     relative path, missing target, in-scope file);
//   - the disclaimer refusal boundary called directly.
//
// What is deliberately NOT ported (no Ycode equivalent exists):
//   - the `@Reverse` message parser (4 checks): Ycode takes structured
//     `reverse_analyze` arguments; there is no message parser.
//   - the JSON bridge request/response encoding, evidence decoding,
//     and error-payload mapping (3 checks): Ycode uses the native REA
//     subsystem, not Legacy's `ReverseBridge` JSON protocol.
//   - the `ReverseBridge.mjs` script check: no bridge script ships
//     in Ycode (see the deviation note in `YcodeTools+Engines.swift`).
//
// No Swift toolchain exists in this environment, so these tests have
// NOT been compiled or run — statically verified only. On Dylan's Mac:
// run with `swift test --filter LegacyReverseGapTests`.

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
        // Legacy's allow-list check: no execution surface and no
        // licensed-tool client may ever appear in the list.
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

    private func expectFailure(_ result: Result<String, String>, _ message: String) {
        if case .success = result {
            Issue.record(message)
        }
    }
}
