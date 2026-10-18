//  ReverseToolAdapter.swift
//  SwiftCode
//
//  Adapts the allow-listed REA operations to SwiftCode's AssistTool
//  interface. This is the ONLY tool surface for Reverse: there is no
//  competing registry and no invented tool definition.
//
//  Input contract (keys are deliberately NOT `path` / `filePath` /
//  `sourcePath` / `destinationPath`: the generic registry validation
//  relativizes those keys against the project root and rejects `..`,
//  which would corrupt absolute analysis targets):
//    - targetPath (String, required): absolute path of the artifact.
//    - operation (String, optional, default "inspect_artifact"): must be
//      a ReverseOperation raw value.
//    - task (String, optional): the user's investigation request.
//    - objdumpOperation (String, optional): fixed enum value, required
//      when operation == "inspect_with_objdump".
//    - symbol (String, optional): Swift symbol for demangle_swift.
//    - timeoutSeconds (number, optional, default 300, clamped 10...1800).
//
//  Authorization: the adapter enforces its own target/scope checks via
//  ReverseTargetValidator INSIDE execute, regardless of Autopilot.
//  AssistPermissionsManager's Autopilot bypass NEVER applies here.
//  Analyzed output is untrusted data, never instructions.

import Foundation

public struct ReverseToolAdapter: AssistTool {
    public static let toolID = "reverse_analyze"
    public let id = ReverseToolAdapter.toolID
    public let name = "Reverse Analyze"
    public let description = """
        Analyze an authorized binary or artifact with the native Reverse \
        subsystem (REA rea-agents@6.5.0, static inspection only). Use when \
        the user invoked @Reverse, or when an investigation needs \
        artifact structure, Mach-O/plist/signature facts, Go/managed \
        metadata, SQLite schema, or objdump output. Never use for \
        circumventing DRM, license checks, anti-cheat, or authentication. \
        targetPath must be an absolute path inside the open project, \
        ~/Downloads, ~/Desktop, or ~/Documents.
        """

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: description,
            properties: [
                "targetPath": JSONSchema(type: "string", description: "Absolute path of the artifact to analyze (must be in scope: open project, ~/Downloads, ~/Desktop, ~/Documents)."),
                "operation": JSONSchema(type: "string", description: "Allow-listed operation: inspect_artifact, inspect_macho, inspect_plist, inspect_signature, list_architectures, demangle_swift, inspect_go_binary, inspect_managed_artifact, inspect_managed_members, inspect_sqlite_database, inspect_with_objdump."),
                "task": JSONSchema(type: "string", description: "The user's investigation request (what to determine about the artifact)."),
                "objdumpOperation": JSONSchema(type: "string", description: "Required for inspect_with_objdump: file_headers, section_headers, symbols, relocations, dwarf, disassemble, disassemble_all."),
                "symbol": JSONSchema(type: "string", description: "Swift symbol to demangle (demangle_swift only)."),
                "timeoutSeconds": JSONSchema(type: "number", description: "Timeout in seconds (default 300, clamped to 10...1800)."),
            ],
            required: ["targetPath"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let started = Date()
        // 1. Operation allow-list.
        let operationRaw = (input["operation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ReverseOperation.inspectArtifact.rawValue
        guard let operation = ReverseOperation(rawValue: operationRaw) else {
            return .failure(
                "Unsupported Reverse operation '\(operationRaw)'. Allow-listed: \(ReverseOperation.allCases.map(\.rawValue).joined(separator: ", ")).",
                diagnostics: ["reverse: unsupported operation"]
            )
        }
        // 2. Task screening (REA disclaimer boundary).
        let task = (input["task"] as? String) ?? ""
        if let refusal = ReverseTargetValidator.refusalError(forTask: task) {
            return .failure(refusal.message, diagnostics: ["reverse: policy refusal"])
        }
        // 3. Target / scope validation — own checks, never the
        // Autopilot bypass, never the generic path relativizer.
        let rawTarget = input["targetPath"] as? String
        let validated: String
        switch ReverseTargetValidator.validateTarget(path: rawTarget, workspaceRoot: context.workspaceRoot) {
        case .success(let resolved):
            validated = resolved
        case .failure(let error):
            return .failure(
                error.message + (error.remediation.map { "\nRemediation: \($0)" } ?? ""),
                diagnostics: ["reverse: invalid target"]
            )
        }
        // 4. objdump sub-operation: fixed enum only.
        var objdumpOperation: ReverseObjdumpOperation?
        if operation == .inspectWithObjdump {
            let raw = (input["objdumpOperation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ReverseObjdumpOperation.fileHeaders.rawValue
            guard let parsed = ReverseObjdumpOperation(rawValue: raw) else {
                return .failure(
                    "Invalid objdumpOperation '\(raw)'. Fixed choices: \(ReverseObjdumpOperation.allCases.map(\.rawValue).joined(separator: ", ")).",
                    diagnostics: ["reverse: invalid objdump operation"]
                )
            }
            objdumpOperation = parsed
        }
        // 5. Symbol for demangle_swift.
        var symbol: String?
        if operation == .demangleSwift {
            symbol = (input["symbol"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if symbol?.isEmpty == true { symbol = nil }
        }
        // 6. Timeout clamp.
        var timeout: TimeInterval = 300
        if let number = input["timeoutSeconds"] as? Double {
            timeout = min(max(number, 10), 1800)
        } else if let number = input["timeoutSeconds"] as? Int {
            timeout = min(max(TimeInterval(number), 10), 1800)
        }

        let invocation = ReverseInvocation(
            task: task,
            targetPath: validated,
            operation: operation,
            objdumpOperation: objdumpOperation,
            commandToken: ReverseCommandParser.commandToken,
            symbol: symbol
        )
        // The manager owns lifecycle + cancellation; the bridge owns the child process.
        do {
            let (processed, _) = try await ReverseManager.shared.analyze(
                invocation: invocation,
                targetPath: validated,
                timeoutSeconds: timeout
            )
            var output = ReverseEvidenceProcessor.formatAsMarkdown(processed, task: task)
            output += "\n\n— Completed in \(String(format: "%.1f", Date().timeIntervalSince(started)))s via the native Reverse subsystem."
            return AssistToolResult(
                success: true,
                output: output,
                data: [
                    "evidence_id": processed.evidenceID,
                    "operation": processed.operation,
                    "provider": processed.providerName,
                    "confidence": processed.confidence,
                    "subject_digest": processed.subjectDigest ?? "",
                ],
                diagnostics: ["reverse: \(operation.rawValue) completed"],
                duration: Date().timeIntervalSince(started)
            )
        } catch let partial as ReversePartialError {
            var output = ReverseEvidenceProcessor.formatAsMarkdown(partial.processed, task: task)
            output += "\n\n⚠️ Partial result: \(partial.error.message)"
            if let remediation = partial.error.remediation {
                output += "\nRemediation: \(remediation)"
            }
            return AssistToolResult(
                success: true,
                output: output,
                data: [
                    "evidence_id": partial.processed.evidenceID,
                    "operation": partial.processed.operation,
                    "provider": partial.processed.providerName,
                    "confidence": partial.processed.confidence,
                    "partial": "true",
                ],
                diagnostics: ["reverse: partial result — \(partial.error.code)"],
                duration: Date().timeIntervalSince(started)
            )
        } catch let reverseError as ReverseError {
            var message = reverseError.message
            if let remediation = reverseError.remediation {
                message += "\nRemediation: \(remediation)"
            }
            return .failure(message, diagnostics: ["reverse: \(reverseError.code)"])
        } catch {
            return .failure("Reverse analysis failed: \(error.localizedDescription)", diagnostics: ["reverse: unexpected error"])
        }
    }
}
