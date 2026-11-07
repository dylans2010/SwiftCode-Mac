import Foundation

public struct ReverseProcessedEvidence: Sendable {
    public let evidenceID: String
    public let operation: String
    public let providerName: String
    public let providerID: String?
    public let confidence: String
    public let subjectPath: String?
    public let subjectDigest: String?
    public let findings: [String]
    public let locations: [ReverseLocation]
    public let limitations: [String]
    public let warnings: [String]
    public let progressTrail: [ReverseProgressEvent]
    public let wasPartial: Bool
    public let boundedResultJSON: String
    public let wasTruncated: Bool

    public init(
        evidenceID: String,
        operation: String,
        providerName: String,
        providerID: String?,
        confidence: String,
        subjectPath: String?,
        subjectDigest: String?,
        findings: [String],
        locations: [ReverseLocation],
        limitations: [String],
        warnings: [String],
        progressTrail: [ReverseProgressEvent],
        wasPartial: Bool,
        boundedResultJSON: String,
        wasTruncated: Bool
    ) {
        self.evidenceID = evidenceID
        self.operation = operation
        self.providerName = providerName
        self.providerID = providerID
        self.confidence = confidence
        self.subjectPath = subjectPath
        self.subjectDigest = subjectDigest
        self.findings = findings
        self.locations = locations
        self.limitations = limitations
        self.warnings = warnings
        self.progressTrail = progressTrail
        self.wasPartial = wasPartial
        self.boundedResultJSON = boundedResultJSON
        self.wasTruncated = wasTruncated
    }
}

public enum ReverseEvidenceProcessor {
    public static let resultJSONBudget = 8_000
    public static let maxFindings = 40
    public static let maxLocations = 40

    public static func process(
        evidence: ReverseEvidence,
        progress: [ReverseProgressEvent] = [],
        wasPartial: Bool = false
    ) -> ReverseProcessedEvidence {
        var findings: [String] = []
        var warnings: [String] = []
        let result = evidence.normalizedResult

        if let substeps = result?.value(forKey: "substeps")?.arrayValue {
            for substep in substeps.prefix(maxFindings) {
                let op = substep.value(forKey: "operation")?.stringValue ?? "substep"
                let status = substep.value(forKey: "status")?.stringValue ?? "unknown status"
                findings.append("\(op): \(status)")
            }
        }
        if let stdout = result?.value(forKey: "stdout")?.stringValue, !stdout.isEmpty {
            let lines = stdout.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for line in lines.prefix(20) {
                findings.append(line)
            }
            if lines.count > 20 {
                findings.append("[\(lines.count - 20) more objdump output lines omitted]")
            }
        }
        if let stderr = result?.value(forKey: "stderr")?.stringValue, !stderr.isEmpty {
            warnings.append("Provider stderr: \(stderr.prefix(500))")
        }
        if let exitCode = result?.value(forKey: "exit_code") {
            if case .number(let code) = exitCode, code != 0 {
                warnings.append("Provider process exited with code \(Int(code)).")
            }
        }
        if let outputTruncated = result?.value(forKey: "output_truncated")?.stringValue {
            if outputTruncated == "true" {
                warnings.append("Upstream output was truncated by the provider.")
            }
        } else if let truncatedValue = result?.value(forKey: "output_truncated"),
                  case .boolean(let truncated) = truncatedValue, truncated {
            warnings.append("Upstream output was truncated by the provider.")
        }
        if findings.isEmpty, let result, case .object(let pairs) = result {
            for pair in pairs.prefix(maxFindings) {
                switch pair.value {
                case .string(let value):
                    findings.append("\(pair.key): \(value.prefix(300))")
                case .number(let value):
                    findings.append("\(pair.key): \(value)")
                case .boolean(let value):
                    findings.append("\(pair.key): \(value)")
                default:
                    break
                }
            }
        }
        if findings.isEmpty {
            findings.append("No structured findings in normalized_result; see the bounded result excerpt below.")
        }

        if let upstreamWarnings = result?.value(forKey: "warnings")?.arrayValue {
            for warning in upstreamWarnings {
                if let text = warning.stringValue { warnings.append(text) }
            }
        }

        let bounded = boundedJSON(result)
        return ReverseProcessedEvidence(
            evidenceID: evidence.evidenceID,
            operation: evidence.operation,
            providerName: evidence.providerName ?? evidence.providerID ?? "REA",
            providerID: evidence.providerID,
            confidence: evidence.confidence ?? "not reported",
            subjectPath: evidence.subjectPath,
            subjectDigest: evidence.subjectDigest,
            findings: Array(findings.prefix(maxFindings)),
            locations: Array(evidence.locations.prefix(maxLocations)),
            limitations: evidence.limitations,
            warnings: warnings,
            progressTrail: progress,
            wasPartial: wasPartial,
            boundedResultJSON: bounded.text,
            wasTruncated: bounded.truncated
        )
    }

    private static func boundedJSON(_ value: ReverseJSONValue?) -> (text: String, truncated: Bool) {
        guard let value else { return ("(no normalized_result)", false) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              var text = String(data: data, encoding: .utf8) else {
            return ("(normalized_result could not be encoded)", false)
        }
        if text.count > resultJSONBudget {
            text = String(text.prefix(resultJSONBudget)) + "\n… [truncated to \(resultJSONBudget) characters]"
            return (text, true)
        }
        return (text, false)
    }

    public static func formatAsMarkdown(_ processed: ReverseProcessedEvidence, task: String) -> String {
        var lines: [String] = []
        lines.append("### Reverse findings — \(processed.operation)")
        if !task.isEmpty {
            lines.append("")
            lines.append("Task: \(task)")
        }
        lines.append("")
        lines.append("- Evidence: `\(processed.evidenceID)`")
        lines.append("- Provider: \(processed.providerName)" + (processed.providerID.map { " (`\($0)`)" } ?? ""))
        lines.append("- Confidence (as reported by REA): \(processed.confidence)")
        if let subject = processed.subjectPath {
            lines.append("- Target: `\(subject)`")
        }
        if let digest = processed.subjectDigest {
            lines.append("- Target SHA-256 (as reported): `\(digest)`")
        }
        if processed.wasPartial {
            lines.append("- ⚠️ Partial result: the operation reported an error after producing this evidence.")
        }
        lines.append("")
        lines.append("#### Observed findings")
        for finding in processed.findings {
            lines.append("- \(finding)")
        }
        if !processed.locations.isEmpty {
            lines.append("")
            lines.append("#### Locations (as reported by REA)")
            for location in processed.locations {
                var parts: [String] = []
                if let kind = location.kind { parts.append(kind) }
                if let path = location.path { parts.append("`\(path)`") }
                if let symbol = location.symbol { parts.append("symbol `\(symbol)`") }
                if let address = location.address { parts.append("address \(address)") }
                if let line = location.line { parts.append("line \(line)") }
                if let detail = location.detail { parts.append(detail) }
                lines.append("- " + parts.joined(separator: " · "))
            }
        }
        if !processed.warnings.isEmpty {
            lines.append("")
            lines.append("#### Warnings")
            for warning in processed.warnings {
                lines.append("- ⚠️ \(warning)")
            }
        }
        if !processed.limitations.isEmpty {
            lines.append("")
            lines.append("#### Limitations (as reported by REA)")
            for limitation in processed.limitations {
                lines.append("- \(limitation)")
            }
        }
        if !processed.progressTrail.isEmpty {
            lines.append("")
            lines.append("#### Progress trail")
            for event in processed.progressTrail {
                lines.append("- [\(event.phase)] \(event.message)")
            }
        }
        lines.append("")
        lines.append("#### Bounded normalized_result excerpt")
        lines.append("```json")
        lines.append(processed.boundedResultJSON)
        lines.append("```")
        if processed.wasTruncated {
            lines.append("Excerpt truncated. Ask a follow-up `@Reverse` question for a different bounded excerpt; full decompilation output is never inlined.")
        }
        return lines.joined(separator: "\n")
    }
}
