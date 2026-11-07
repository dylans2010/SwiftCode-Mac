import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftCodeAssistant
import SwiftCodeIDECore

extension SwiftCodeMCPHost {
    struct DependencyAuditPackage: Sendable, Equatable {
        var name: String
        var repositoryURL: String
        var version: String?
        var skipReason: String?
    }

    nonisolated(unsafe) static var dependencyAuditTestFetcher: (@Sendable (Data) async throws -> Data)?

    nonisolated static func dependencyAuditPackages(from data: Data) throws -> [DependencyAuditPackage] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPToolError("Package.resolved is not a JSON object")
        }
        let rawPins: [[String: Any]]
        if let pins = root["pins"] as? [[String: Any]] { rawPins = pins }
        else if let object = root["object"] as? [String: Any], let pins = object["pins"] as? [[String: Any]] {
            rawPins = pins
        } else { return [] }
        var out: [DependencyAuditPackage] = []
        for pin in rawPins {
            let state = pin["state"] as? [String: Any] ?? [:]
            let name = (pin["identity"] as? String) ?? (pin["package"] as? String) ?? "unknown"
            var location = (pin["location"] as? String) ?? (pin["repositoryURL"] as? String) ?? ""
            if location.isEmpty, let url = pin["url"] as? String { location = url }
            if let version = state["version"] as? String, !version.isEmpty {
                out.append(DependencyAuditPackage(name: name, repositoryURL: location, version: version))
                continue
            }
            var reason: String
            if location.isEmpty || location.hasPrefix("/") || location.hasPrefix("file:") {
                reason = "local path dependency"
            } else if let branch = state["branch"] as? String {
                reason = "pinned to branch '\(branch)' (no version)"
            } else if state["revision"] != nil {
                reason = "pinned to a revision (no version)"
            } else {
                reason = "no pinned version"
            }
            out.append(DependencyAuditPackage(name: name, repositoryURL: location, version: nil, skipReason: reason))
        }
        return out
    }

    nonisolated static func dependencyAuditQueryBody(_ packages: [DependencyAuditPackage]) -> Data {
        let queries: [[String: Any]] = packages.compactMap { pkg in
            guard let version = pkg.version else { return nil }
            return ["package": ["name": pkg.repositoryURL, "ecosystem": "SwiftURL"], "version": version]
        }
        return (try? JSONSerialization.data(withJSONObject: ["queries": queries])) ?? Data()
    }

    struct DependencyAuditVulnerability: Sendable {
        var id: String
        var packageName: String
        var summary: String
        var severity: String?
        var affected: String
        var fixedVersion: String?
        var reference: String?
        var json: AnyJSON { .object([
            "id": .string(id), "package": .string(packageName), "summary": .string(summary),
            "severity": severity.map(AnyJSON.string) ?? .null,
            "affected": .string(affected),
            "fixedVersion": fixedVersion.map(AnyJSON.string) ?? .null,
            "reference": reference.map(AnyJSON.string) ?? .null]) }
    }

    nonisolated static func dependencyAuditParseBatch(_ data: Data, packages: [DependencyAuditPackage]) -> [(package: DependencyAuditPackage, id: String, summary: String)] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return [] }
        var out: [(DependencyAuditPackage, String, String)] = []
        for (index, result) in results.enumerated() where index < packages.count {
            guard let vulns = result["vulns"] as? [[String: Any]] else { continue }
            for vuln in vulns {
                guard let id = vuln["id"] as? String else { continue }
                out.append((packages[index], id, vuln["summary"] as? String ?? ""))
            }
        }
        return out
    }

    nonisolated static func dependencyAuditParseDetail(_ data: Data, package: DependencyAuditPackage, id: String, summary: String) -> DependencyAuditVulnerability {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        var severity: String?
        if let list = root["severity"] as? [[String: Any]] {
            severity = list.first(where: { ($0["type"] as? String) == "CVSS_V3" || ($0["type"] as? String) == "CVSS_V4" })?["score"] as? String
                ?? list.first?["score"] as? String
        }
        var affectedParts: [String] = []
        var fixed: String?
        if let affected = root["affected"] as? [[String: Any]] {
            for entry in affected {
                if let ranges = entry["ranges"] as? [[String: Any]] {
                    for range in ranges {
                        let events = (range["events"] as? [[String: Any]] ?? []).compactMap { e -> String? in
                            if let v = e["introduced"] as? String { return "introduced \(v)" }
                            if let v = e["fixed"] as? String { fixed = v; return "fixed \(v)" }
                            if let v = e["limit"] as? String { return "limit \(v)" }
                            return nil
                        }
                        if !events.isEmpty { affectedParts.append(events.joined(separator: ", ")) }
                    }
                }
            }
        }
        let reference = (root["references"] as? [[String: Any]])?.first?["url"] as? String
        return DependencyAuditVulnerability(id: id, packageName: package.name,
                                            summary: summary.isEmpty ? (root["summary"] as? String ?? id) : summary,
                                            severity: severity,
                                            affected: affectedParts.isEmpty ? "unknown" : affectedParts.joined(separator: "; "),
                                            fixedVersion: fixed, reference: reference)
    }

    private func dependencyAuditQueryBatch(_ body: Data) async throws -> Data {
        if let fetcher = Self.dependencyAuditTestFetcher { return try await fetcher(body) }
        var request = URLRequest(url: URL(string: "https://api.osv.dev/v1/querybatch")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let response = try await HTTP.send(request, timeout: 30)
        guard response.status == 200 else {
            throw MCPToolError("OSV querybatch failed (HTTP \(response.status)): \(response.text.prefix(300))")
        }
        return response.body
    }

    private func dependencyAuditFetchDetail(id: String) async throws -> Data {
        if let fetcher = Self.dependencyAuditTestFetcher { return try await fetcher(Data()) }
        var request = URLRequest(url: URL(string: "https://api.osv.dev/v1/vulns/\(id)")!)
        request.httpMethod = "GET"
        let response = try await HTTP.send(request, timeout: 30)
        guard response.status == 200 else {
            throw MCPToolError("OSV vulns/\(id) failed (HTTP \(response.status))")
        }
        return response.body
    }

    func dependencyAudit(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let rawProjectPath = call.string("projectPath"), !rawProjectPath.isEmpty else {
            throw MCPToolError("Missing projectPath")
        }
        let root: URL
        do {
            root = try resolveFileReadingPath(rawProjectPath, in: s)
        } catch {
            throw MCPToolError("Invalid projectPath '\(rawProjectPath)': paths must stay inside the workspace.")
        }
        let resolvedURL = root.appendingPathComponent("Package.resolved")
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            throw MCPToolError("No Package.resolved in \(root.path) — nothing to audit. (Run a build or resolve the package first.)")
        }
        let data = try Data(contentsOf: resolvedURL)
        let packages = try Self.dependencyAuditPackages(from: data)
        let auditable = packages.filter { $0.version != nil }
        let skipped = packages.filter { $0.version == nil }
        guard !auditable.isEmpty else {
            let reasons = skipped.map { "\($0.name): \($0.skipReason ?? "not auditable")" }.joined(separator: "; ")
            throw MCPToolError("No version-pinned dependencies to audit in Package.resolved (\(reasons.isEmpty ? "no pins" : reasons)).")
        }
        var found: [(package: DependencyAuditPackage, id: String, summary: String)] = []
        for chunk in auditable.chunked(into: 100) {
            let body = Self.dependencyAuditQueryBody(chunk)
            let response = try await dependencyAuditQueryBatch(body)
            found += Self.dependencyAuditParseBatch(response, packages: chunk)
        }
        var vulns: [DependencyAuditVulnerability] = []
        for hit in found.prefix(50) {
            let detail = try await dependencyAuditFetchDetail(id: hit.id)
            vulns.append(Self.dependencyAuditParseDetail(detail, package: hit.package, id: hit.id, summary: hit.summary))
        }
        let checked = ISO8601DateFormatter().string(from: Date())
        let skippedJSON: [AnyJSON] = skipped.map { .object([
            "package": .string($0.name), "reason": .string($0.skipReason ?? "not auditable")]) }
        let summary: String
        if vulns.isEmpty {
            summary = "No advisories reported by OSV for \(auditable.count) pinned dependencies (checked \(checked)). " +
                "This is not a guarantee of safety: OSV matches advisories whose affected package URL matches the repository URL in Package.resolved, and advisory coverage varies by ecosystem."
        } else {
            let extra = found.count > 50 ? " (showing first 50 of \(found.count) advisories)" : ""
            let lines = vulns.map { v in
                var line = "- \(v.id) (\(v.packageName)): \(v.summary)"
                if let sev = v.severity { line += " [CVSS \(sev)]" }
                if let fixed = v.fixedVersion { line += " — fixed in \(fixed)" }
                if let ref = v.reference { line += " — \(ref)" }
                return line
            }
            summary = "OSV reported \(vulns.count) advisories for \(auditable.count) pinned dependencies (checked \(checked))\(extra):\n" + lines.joined(separator: "\n")
        }
        return .structured(["packageCount": .int(packages.count), "auditedCount": .int(auditable.count),
                            "skippedCount": .int(skipped.count), "vulnerableCount": .int(vulns.count),
                            "vulnerabilities": .array(vulns.map(\.json)),
                            "skipped": .array(skippedJSON)], summary: summary)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var out: [[Element]] = []
        var i = 0
        while i < count { out.append(Array(self[i..<Swift.min(i + size, count)])); i += size }
        return out
    }
}
