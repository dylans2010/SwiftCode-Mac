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
        let operationRaw = (input["operation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ReverseOperation.inspectArtifact.rawValue
        guard let operation = ReverseOperation(rawValue: operationRaw) else {
            return .failure(
                "Unsupported Reverse operation '\(operationRaw)'. Allow-listed: \(ReverseOperation.allCases.map(\.rawValue).joined(separator: ", ")).",
                diagnostics: ["reverse: unsupported operation"]
            )
        }
        let task = (input["task"] as? String) ?? ""
        if let refusal = ReverseTargetValidator.refusalError(forTask: task) {
            return .failure(refusal.message, diagnostics: ["reverse: policy refusal"])
        }
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
        var symbol: String?
        if operation == .demangleSwift {
            symbol = (input["symbol"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if symbol?.isEmpty == true { symbol = nil }
        }
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
