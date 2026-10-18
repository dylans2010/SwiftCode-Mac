//  ReverseTests.swift
//  SwiftCode
//
//  Reverse subsystem tests, in the app's Sources (there is no XCTest
//  target in this project). Wired into AssistRuntimeTestSuite.
//
//  These tests cover parsing, validation, evidence provenance, error
//  mapping, and the allow-list. They do NOT prove real REA analysis
//  works: the bridge's real-REA verification is the recorded
//  out-of-repo run documented in Docs/Assist-Reverse-REA-Audit-and-Plan.md
//  (real Evidence from inspect_artifact + inspect_with_objdump).

import Foundation

public enum ReverseTestSuite {
    public static func runAll() async -> [RuntimeTestCaseResult] {
        [
            check("Reverse: parser recognizes intentional invocation") {
                guard let parsed = ReverseCommandParser.parse(message: "@Reverse /tmp/sample-bin Inspect how configuration loading works") else {
                    return "parse returned nil for a valid invocation"
                }
                guard parsed.targetPath == "/tmp/sample-bin" else { return "target mismatch: \(parsed.targetPath ?? "nil")" }
                guard parsed.operation == .inspectArtifact else { return "default operation should be inspect_artifact" }
                guard parsed.task.contains("Inspect how configuration loading works") else { return "task not preserved: '\(parsed.task)'" }
                return nil
            },
            check("Reverse: parser rejects incidental prose mentions") {
                if ReverseCommandParser.parse(message: "I read about @Reverse yesterday") != nil {
                    return "incidental prose mention must not parse"
                }
                if ReverseCommandParser.parse(message: "The @ReverseXYZ command is new") != nil {
                    return "@ReverseXYZ must not parse (token must be followed by end/whitespace)"
                }
                if ReverseCommandParser.parse(message: "Please run @Reverse /tmp/x") != nil {
                    return "mid-message @Reverse must not parse (must be at start)"
                }
                return nil
            },
            check("Reverse: parser accepts lowercase and bare command") {
                guard ReverseCommandParser.parse(message: "@reverse /tmp/x inspect") != nil else {
                    return "lowercase @reverse should parse"
                }
                guard let bare = ReverseCommandParser.parse(message: "@Reverse") else {
                    return "bare @Reverse should parse (adapter returns actionable error)"
                }
                guard bare.targetPath == nil && bare.task.isEmpty else {
                    return "bare @Reverse should have no target/task"
                }
                return nil
            },
            check("Reverse: parser resolves op= and objdump sub-operation") {
                guard let macho = ReverseCommandParser.parse(message: "@Reverse /tmp/a op=inspect_macho list architectures") else {
                    return "op= parse failed"
                }
                guard macho.operation == .inspectMacho else { return "op=inspect_macho not resolved" }
                guard let objdump = ReverseCommandParser.parse(message: "@Reverse /tmp/a objdump symbols") else {
                    return "objdump parse failed"
                }
                guard objdump.operation == .inspectWithObjdump, objdump.objdumpOperation == .symbols else {
                    return "objdump symbols not resolved: \(objdump.operation) \(objdump.objdumpOperation?.rawValue ?? "nil")"
                }
                return nil
            },
            check("Reverse: allow-list excludes execution surfaces and licensed-tool clients") {
                let raw = ReverseOperation.allCases.map(\.rawValue)
                let forbidden = ["execute_rizin_command", "frida", "gdb", "ida", "jeb", "jadx", "adb", "extract_firmware", "instrument"]
                for item in forbidden where raw.contains(where: { $0.contains(item) }) {
                    return "allow-list must not contain '\(item)'"
                }
                guard ReverseOperation.allCases.count == 11 else {
                    return "allow-list drift: expected 11 operations, got \(ReverseOperation.allCases.count)"
                }
                guard ReverseOperation.allCases.allSatisfy(\.isStaticOnly) else {
                    return "every allow-listed operation must be static-only"
                }
                guard !raw.contains(where: { $0.contains("mcp") }) else {
                    return "allow-list must not reference the forbidden transport"
                }
                return nil
            },
            check("Reverse: bridge request/response encoding and correlation") {
                let encoder = JSONEncoder()
                let request = ReverseBridgeRequest(
                    id: "corr-1", method: "analyze",
                    params: ReverseBridgeParams(operation: "inspect_artifact", targetPath: "/tmp/x", task: "t")
                )
                let data = try encoder.encode(request)
                let decoded = try JSONDecoder().decode(ReverseBridgeRequest.self, from: data)
                guard decoded.version == ReverseBridgeProtocol.version else { return "version mismatch" }
                guard decoded.id == "corr-1", decoded.method == "analyze" else { return "id/method mismatch" }
                guard decoded.params?.operation == "inspect_artifact" else { return "params not preserved" }
                return nil
            },
            check("Reverse: evidence decoding preserves provenance, never invents it") {
                let json = """
                {"version":1,"id":"e1","type":"result","evidence":{"evidence_id":"ev_test","subject":{"name":"sample-bin","digest":{"sha256":"abc"},"local_path":"/tmp/sample-bin","format":"elf"},"provider":{"id":"gnu.objdump","name":"GNU objdump","version":null},"operation":"inspect_with_objdump","confidence":"observed","normalized_result":{"stdout":"file format elf64-x86-64\\n","exit_code":0},"limitations":["limitation one"],"locations":[{"kind":"artifact-path","path":"/tmp/sample-bin"}]}}
                """
                let message = try JSONDecoder().decode(ReverseBridgeMessage.self, from: Data(json.utf8))
                guard let evidence = message.evidence else { return "evidence missing" }
                guard evidence.evidenceID == "ev_test" else { return "evidence_id mismatch" }
                guard evidence.providerID == "gnu.objdump" else { return "provider not preserved" }
                guard evidence.confidence == "observed" else { return "confidence not preserved" }
                guard evidence.locations.count == 1, evidence.locations.first?.path == "/tmp/sample-bin" else {
                    return "locations not preserved"
                }
                guard evidence.limitations == ["limitation one"] else { return "limitations not preserved" }
                // No confidence supplied -> "not reported", never invented.
                let noConfidence = """
                {"version":1,"id":"e2","type":"result","evidence":{"evidence_id":"ev2","operation":"inspect_artifact","normalized_result":{},"limitations":[],"locations":[]}}
                """
                let message2 = try JSONDecoder().decode(ReverseBridgeMessage.self, from: Data(noConfidence.utf8))
                let processed = ReverseEvidenceProcessor.process(evidence: message2.evidence!)
                guard processed.confidence == "not reported" else { return "missing confidence must render as 'not reported', got '\(processed.confidence)'" }
                guard processed.locations.isEmpty else { return "missing locations must stay empty" }
                return nil
            },
            check("Reverse: bridge error payload maps to typed categories") {
                let json = """
                {"version":1,"id":"e3","type":"error","error":{"code":"capability_unavailable","category":"unsupportedOperation","message":"This analysis is unavailable for the current target.","retryable":false,"remediation":"Choose another analysis."}}
                """
                let message = try JSONDecoder().decode(ReverseBridgeMessage.self, from: Data(json.utf8))
                guard let payload = message.error else { return "error payload missing" }
                let error = ReverseError.fromBridgePayload(payload)
                guard error.category == .unsupportedOperation else { return "category mismatch: \(error.category)" }
                guard error.retryable == false, error.remediation == "Choose another analysis." else {
                    return "retryable/remediation not preserved"
                }
                return nil
            },
            check("Reverse: target validation blocks system paths, traversal, and out-of-scope") {
                let root = URL(fileURLWithPath: "/tmp")
                switch ReverseTargetValidator.validateTarget(path: "/System/Library/Fonts/x", workspaceRoot: root) {
                case .failure: break
                case .success: return "/System target must be rejected"
                }
                switch ReverseTargetValidator.validateTarget(path: "/tmp/../etc/passwd", workspaceRoot: root) {
                case .failure: break
                case .success: return "'..' target must be rejected"
                }
                switch ReverseTargetValidator.validateTarget(path: "relative/path", workspaceRoot: root) {
                case .failure: break
                case .success: return "relative target must be rejected"
                }
                switch ReverseTargetValidator.validateTarget(path: nil, workspaceRoot: root) {
                case .failure: break
                case .success: return "missing target must be rejected"
                }
                // In-scope positive case: real file inside the workspace root.
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reverse-test-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: dir) }
                let file = dir.appendingPathComponent("sample")
                try Data([0x7F, 0x45, 0x4C, 0x46]).write(to: file)
                switch ReverseTargetValidator.validateTarget(path: file.path, workspaceRoot: dir) {
                case .success(let resolved): guard resolved == file.resolvingSymlinksInPath().path else { return "resolved path mismatch" }
                case .failure(let error): return "in-scope file must validate: \(error.message)"
                }
                return nil
            },
            check("Reverse: disclaimer boundary refuses DRM/license/anti-cheat tasks") {
                guard ReverseTargetValidator.refusalError(forTask: "bypass DRM on this game") != nil else {
                    return "DRM bypass task must be refused"
                }
                guard ReverseTargetValidator.refusalError(forTask: "find how to circumvent the license check") != nil else {
                    return "license-check circumvention must be refused"
                }
                guard ReverseTargetValidator.refusalError(forTask: "inspect how this authorized binary loads its config") == nil else {
                    return "legitimate investigation must not be refused"
                }
                return nil
            },
            check("Reverse: bridge script has no forbidden-transport or free-form execution surface") {
                guard let url = Bundle.main.url(forResource: "ReverseBridge", withExtension: "mjs") else {
                    return "ReverseBridge.mjs missing from bundle resources"
                }
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                guard !text.lowercased().contains("modelcontextprotocol") else {
                    return "bridge must not reference the forbidden transport implementation"
                }
                guard text.contains("runDirectAnalysis") else {
                    return "bridge must use the direct REA import path"
                }
                guard text.contains("inspect-with-objdump") else {
                    return "bridge must contain the scoped objdump CLI fallback"
                }
                guard !text.contains("execute_rizin_command") else {
                    return "bridge must not contain the free-form Rizin operation"
                }
                return nil
            },
        ]
    }

    private static func check(_ name: String, _ body: () throws -> String?) -> RuntimeTestCaseResult {
        let start = Date()
        do {
            if let failure = try body() {
                return RuntimeTestCaseResult(testName: name, passed: false, message: failure, duration: Date().timeIntervalSince(start))
            }
            return RuntimeTestCaseResult(testName: name, passed: true, message: "Passed.", duration: Date().timeIntervalSince(start))
        } catch {
            return RuntimeTestCaseResult(testName: name, passed: false, message: "Threw: \(error.localizedDescription)", duration: Date().timeIntervalSince(start))
        }
    }
}
