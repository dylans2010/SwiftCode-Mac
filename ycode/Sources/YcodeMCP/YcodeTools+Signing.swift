import Foundation
import YcodeAssistant
import YcodeIDECore
import YcodeProject
import YcodeSettings
import YcodeWorkspace

/// The ported Legacy signing / entitlements / plist tool family (Wave 7,
/// slice D).
///
/// Behaviour source: Legacy's `AssistCodeSigningDiagnoseTool`,
/// `AssistEntitlementsDiffTool`, `AssistEntitlementsTool`,
/// `AssistInfoPlistAuditTool`, `AssistPlistTool`,
/// `AssistProjectEntitlementsTool`, `AssistProjectInfoPlistTool`,
/// `AssistProjectSigningTool`, `AssistProvisioningCheckTool`,
/// `AssistProvisioningProfileReaderTool` and
/// `AssistSigningCertificateInspectorTool` (Dylan's own code, ported
/// under MIT). The behaviour contract, including the per-tool error
/// strings and the `plist_editor` vs `plist_edit` distinction, is
/// `~/SwiftCode-Migration-Workspace/scratch/wave7-slice-d-spec.md`.
///
/// Conventions, following Waves 1–6:
///
/// * Schemas are Legacy's `parametersSchema` verbatim, plus the
///   `workspace` parameter every Ycode tool carries. Legacy's
///   parameter-name aliases are NOT supported: Ycode's argument
///   validation rejects unknown arguments before the handler runs.
///   The four aliases for this slice (`plist` → `plist_editor`,
///   `entitlements` → `entitlements_manager`, `signing_certificate`
///   → `signing_certificate_inspector`, `provisioning_profile` →
///   `provisioning_profile_reader`, from Legacy's
///   `AssistToolRegistry` alias table) live in
///   `MCPServer.toolAliases`, which the coordinator owns — they are
///   not added here.
/// * Structured data keeps Legacy's keys, with typed JSON values
///   (integers, booleans) the way Ycode's other tools do — Legacy's
///   string-only map is not reproduced. Tools whose Legacy result
///   carries no data return a plain text result instead.
/// * Paths resolve through the session resolvers and never escape
///   the workspace, with two deliberate, read-only exceptions
///   documented in the spec: `provisioning_profile_reader` accepts
///   an explicit absolute path as-is (profiles live in
///   `~/Library/MobileDevice/Provisioning Profiles`, outside any
///   workspace — the same exception Wave 6 made for
///   `test_coverage_reporter`'s explicit report path), and
///   `project_signing` / `provisioning_check` read that installed
///   profiles directory itself.
/// * Approval gating: the three writing tools
///   (`entitlements_manager`, `plist_editor`, `project_info_plist`)
///   are `writes: true` with `safeMutation` annotations. Text writes
///   go through `commit()`; a `plist_editor` set/delete that
///   preserves a binary source format goes through
///   `approveFileWritingChange` + a direct `Data` write, the
///   `json_to_plist` shape. `MCPServer.run()` already refuses
///   `writes: true` tools when the server is read-only; the approval
///   call is still required. There is no Autopilot bypass. Because
///   the `writes` flag is static per tool, the read-only actions of
///   the writing tools are refused in `readOnly` mode too — the same
///   documented consequence as Wave 6's `test_snapshot_manage`
///   `list`.
/// * External processes run through the fixed-argv runner from
///   `YcodeTools+TerminalSupport.swift` (`terminalRunFixed`, off the
///   main actor, no shell, 60 s timeout): `/usr/bin/codesign` and
///   `/usr/bin/security`. No process is ever spawned from a shell
///   string, and no argument is ever built from tool input beyond
///   the single resolved file path.
/// * Signing/certificate/provisioning inspection reads the local
///   keychain and installed profiles and reports real state. Nothing
///   invents credentials or identities, and no secret material is
///   ever emitted: `signing_certificate_inspector` reports only the
///   names and SHA-1 hashes `security find-identity` itself prints,
///   and the provisioning tools report profile metadata and
///   entitlements only — never the `DeveloperCertificates` blobs.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `project_signing`: Legacy spawns `xcodebuild -showBuildSettings`
///   (macOS-only). This port resolves the five signing settings from
///   the workspace's own `.xcodeproj` through Ycode's
///   `ProjectSettingsBuilder` — the same seam the `build_settings`
///   tool uses — so it works wherever the project opens and honours
///   `.xcconfig` base configurations. The target resolved is the
///   first target, or the target whose name matches `scheme` when
///   one is given (Legacy's scheme selected the target implicitly
///   through xcodebuild); a `configuration` the project does not
///   define falls back to the project's default configuration, the
///   builder's own rule. A workspace with no `.xcodeproj` /
///   `.xcworkspace` fails with Legacy's message.
/// * `code_signing_diagnose`: `codesign -dv` writes its report to
///   stderr, so stdout and stderr are combined before parsing
///   (Legacy's runner merged both streams). On a host without
///   `/usr/bin/codesign` the handler fails cleanly instead of
///   reporting a fake diagnosis.
/// * `provisioning_check` / `provisioning_profile_reader` /
///   `signing_certificate_inspector`: on a host without
///   `/usr/bin/security` the handler fails cleanly with Legacy's
///   message shape instead of reporting an empty result (an empty
///   certificate/profile list would be a lie on a machine whose
///   keychain was never consulted). YcodeSigning's pure-Swift CMS
///   decoder (`ProvisioningProfile`) is NOT used here: `YcodeMCP`
///   has no target dependency on `YcodeSigning` and `Package.swift`
///   is out of scope for this slice, so no parallel signing model
///   was built. If a later wave adds that dependency, the two
///   provisioning tools are the candidates to move onto it (which
///   would also make them work on Linux).
/// * `plist_editor` preserves the source plist's format on write
///   (XML stays XML, binary stays binary), as Legacy does; the
///   binary case is the one place a `Data` write is used instead of
///   `commit()`. `plist_editor` performs no verification re-read
///   (Legacy does none here — unlike `plist_edit` /
///   `project_info_plist`).
/// * `entitlements_manager` validates no entitlement key against any
///   policy (YcodeSigning's `EntitlementPolicy` is not reachable
///   from this target); any key string is accepted, as in Legacy.
/// * Path handling is tightened where Legacy appended a path to the
///   workspace root unchecked (`plist_editor`,
///   `project_info_plist`, `entitlements_manager`): the strict
///   session resolver (`resolveFileWritingPath`) is used, so a path
///   that would escape the workspace fails with the tool's own
///   Legacy message instead of being followed.
extension YcodeMCPHost {
    var signingTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        return [
            tool("code_signing_diagnose", "Code Signing Diagnose",
                 "Diagnoses code-signing state of a built .app/.framework: signature validity, authority chain, team identifier, and hardened-runtime flags.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the .app, .framework, or binary.")],
                                      required: ["path"]),
                 output: Schema.output(["exitCode": Schema.int, "teamIdentifier": Schema.str,
                                        "authority": Schema.str, "signed": Schema.bool])) { h, call in
                try await h.signingDiagnoseCodeSigning(call)
            },
            tool("entitlements_diff", "Entitlements Diff",
                 "Compares two .entitlements plist files, reporting added, removed, and changed keys.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "oldPath": Schema.string("Workspace-relative path to the baseline .entitlements file."),
                                       "newPath": Schema.string("Workspace-relative path to the new .entitlements file.")],
                                      required: ["oldPath", "newPath"]),
                 output: Schema.output(["added": Schema.int, "removed": Schema.int, "changed": Schema.int])) { h, call in
                try h.signingDiffEntitlements(call)
            },
            tool("entitlements_manager", "Entitlements Manager",
                 "Inspects, adds, and removes Apple security entitlements (.entitlements) like App Sandbox and Network access.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Action: 'inspect', 'add_entitlement', 'remove_entitlement', 'list'."),
                                       "filePath": Schema.string("Workspace-relative path to the .entitlements file."),
                                       "entitlementKey": Schema.string("Entitlement key (e.g. 'com.apple.security.app-sandbox' or 'com.apple.security.network.client')."),
                                       "value": Schema.string("Value for entitlement (default 'true').")],
                                      required: ["action", "filePath"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.signingManageEntitlements(call)
            },
            tool("info_plist_audit", "Info.plist Audit",
                 "Audits Info.plist files for required keys, version-format sanity, and duplicate bundle identifiers.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["fileCount": Schema.int, "issueCount": Schema.int])) { h, call in
                try h.signingAuditInfoPlist(call)
            },
            tool("plist_editor", "Property List Editor",
                 "Inspects, sets, deletes, and validates keys in Apple Property List (.plist) files.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Action: 'read', 'set', 'delete', 'list_keys'."),
                                       "filePath": Schema.string("Workspace-relative path to the .plist file."),
                                       "key": Schema.string("Property list key to read, set, or delete."),
                                       "value": Schema.string("Value to write (for 'set')."),
                                       "valueType": Schema.string("Type of value: 'string', 'boolean', 'integer' (defaults to string).")],
                                      required: ["action", "filePath"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.signingEditPlist(call)
            },
            tool("project_entitlements", "Entitlements",
                 "Finds and parses .entitlements files in the workspace and returns their keys and values.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Optional workspace-relative path to a specific .entitlements file.")]),
                 output: Schema.output(["files": Schema.str, "keys": Schema.str, "count": Schema.int])) { h, call in
                try h.signingProjectEntitlements(call)
            },
            tool("project_info_plist", "Info.plist Editor",
                 "Reads and edits Info.plist keys using PropertyListSerialization with atomic writes and verification.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("get, set, or delete. Default: get."),
                                       "key": Schema.string("Plist key. Required for set and delete."),
                                       "value": Schema.string("New value for set. Interpreted as Bool for true/false, Int for integers, otherwise String."),
                                       "path": Schema.string("Optional workspace-relative path to a specific Info.plist. Defaults to the first Info.plist found.")]),
                 output: Schema.output(["key": Schema.str, "value": Schema.str, "file": Schema.str,
                                        "keys": Schema.str, "count": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.signingEditProjectInfoPlist(call)
            },
            tool("project_signing", "Signing Check",
                 "Checks code-signing build settings and lists installed provisioning profile filenames without parsing profile contents.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "scheme": Schema.string("Optional scheme name for -showBuildSettings."),
                                       "configuration": Schema.string("Build configuration, e.g. Debug or Release. Default: Debug.")]),
                 output: Schema.output(["configuration": Schema.str, "codeSignStyle": Schema.str, "developmentTeam": Schema.str,
                                        "bundleId": Schema.str, "codeSignIdentity": Schema.str,
                                        "provisioningProfileSpecifier": Schema.str, "provisioningProfileCount": Schema.int,
                                        "provisioningProfiles": Schema.str, "scheme": Schema.str])) { h, call in
                try h.signingCheckProjectSigning(call)
            },
            tool("provisioning_check", "Provisioning Check",
                 "Lists installed provisioning profiles, reports expiration, and compares App IDs against an optional bundle ID.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "bundleId": Schema.string("Bundle ID to compare against each profile App ID (optional).")]),
                 output: Schema.output(["profile_count": Schema.int, "expired_count": Schema.int, "expiring_count": Schema.int,
                                        "match_count": Schema.int, "mismatch_count": Schema.int, "bundle_id": Schema.str])) { h, call in
                try await h.signingCheckProvisioning(call)
            },
            tool("provisioning_profile_reader", "Provisioning Profile Reader",
                 "Decodes and inspects entitlements, team ID, and expiration date of Apple provisioning profiles.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Path to .mobileprovision or .provisionprofile file.")],
                                      required: ["path"])) { h, call in
                try await h.signingReadProvisioningProfile(call)
            },
            tool("signing_certificate_inspector", "Code Signing Certificate Inspector",
                 "Inspects valid Apple Development and Distribution code signing certificates in the keychain.",
                 input: Schema.object(["workspace": Schema.workspace])) { h, call in
                try await h.signingInspectSigningCertificates(call)
            },
        ]
    }

    // MARK: - Shared helpers for the signing tools

    /// A dictionary plist at `url`, with the format it was read in
    /// (so a writer can preserve it). `nil` when the file cannot be
    /// read or is not a dictionary plist.
    func signingReadPlistDictionary(at url: URL) -> (dict: [String: Any], format: PropertyListSerialization.PropertyListFormat)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: &format),
              let dict = plist as? [String: Any] else { return nil }
        return (dict, format)
    }

    /// Legacy's `stringValue`: booleans as true/false, arrays as
    /// `[a, b]`, dictionaries as `{k = v, …}` with sorted keys,
    /// everything else via `"\(value)"`.
    func signingPlistString(_ value: Any?) -> String {
        guard let value else { return "null" }
        if let boolValue = value as? Bool { return boolValue ? "true" : "false" }
        if let array = value as? [Any] { return "[" + array.map { signingPlistString($0) }.joined(separator: ", ") + "]" }
        if let dict = value as? [String: Any] {
            return "{" + dict.keys.sorted().map { "\($0) = \(signingPlistString(dict[$0]))" }.joined(separator: ", ") + "}"
        }
        return "\(value)"
    }

    /// Legacy `AssistProjectInfoPlistTool.plistValue`: Bool for
    /// true/false (case-insensitive), Int for integers, Double for
    /// decimals, otherwise the string as-is.
    func signingPlistValue(from string: String) -> Any {
        let lower = string.lowercased()
        if lower == "true" { return true }
        if lower == "false" { return false }
        if let intValue = Int(string) { return intValue }
        if let doubleValue = Double(string) { return doubleValue }
        return string
    }

    /// Every file under the workspace root (hidden files skipped,
    /// sorted by path) for which `matches` holds.
    func signingWorkspaceFiles(in s: WorkspaceSession, matching: (URL) -> Bool) -> [URL] {
        let root = Self.folder(of: s.model)
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return results
        }
        for case let url as URL in enumerator where matches(url) { results.append(url) }
        return results.sorted { $0.path < $1.path }
    }

    /// The first `Info.plist` in the workspace, skipping build
    /// outputs (Legacy's exclusion for `project_info_plist`).
    func signingFindInfoPlist(in s: WorkspaceSession) -> URL? {
        signingWorkspaceFiles(in: s) { url in
            guard url.lastPathComponent == "Info.plist" else { return false }
            let path = url.path
            return !path.contains("/build/") && !path.contains("/DerivedData/") && !path.contains("/.build/")
        }.first
    }

    /// `~/Library/MobileDevice/Provisioning Profiles`.
    func signingProfilesDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/MobileDevice/Provisioning Profiles")
    }

    /// Filenames (only) of the installed `.mobileprovision` profiles.
    func signingInstalledProfileNames() -> [String] {
        let dir = signingProfilesDirectory()
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return entries.filter { $0.pathExtension == "mobileprovision" }.map(\.lastPathComponent).sorted()
    }

    /// Decodes one profile with `security cms -D`. The decoded plist
    /// dictionary, or `nil` when the tool is absent, the launch
    /// fails, the exit code is non-zero, or the output is not a
    /// plist — with stderr alongside for the caller's message.
    func signingDecodeProfile(at url: URL) -> (dict: [String: Any]?, stderr: String) {
        guard let run = Self.terminalRunFixed("/usr/bin/security", ["cms", "-D", "-i", url.path], timeout: 60) else {
            return (nil, "")
        }
        guard run.exitCode == 0, !run.timedOut,
              let data = run.stdout.data(using: .utf8) else {
            return (nil, run.stderr)
        }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format),
              let dict = plist as? [String: Any] else { return (nil, run.stderr) }
        return (dict, run.stderr)
    }

    // MARK: - code_signing_diagnose

    func signingDiagnoseCodeSigning(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing required parameter: path")
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL
        do {
            url = try resolveFileReadingPath(trimmed, in: s)
        } catch {
            throw MCPToolError("No file at path: \(trimmed)")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("No file at path: \(trimmed)")
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/codesign") else {
            throw MCPToolError("Code signing diagnosis requires macOS with /usr/bin/codesign; it is not available on this platform.")
        }
        guard let run = Self.terminalRunFixed("/usr/bin/codesign", ["-dv", "--verbose=4", url.path], timeout: 60) else {
            throw MCPToolError("Failed to run codesign: could not launch /usr/bin/codesign")
        }
        if run.timedOut {
            throw MCPToolError("codesign timed out after 60s on \(trimmed).")
        }
        // `codesign -dv` writes its report to stderr; Legacy's runner
        // merged both streams, so this port combines them too.
        let output = run.stdout + run.stderr
        var info: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { info[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1] }
        }
        var findings: [String] = []
        if output.contains("code object is not signed") {
            findings.append("NOT SIGNED: the product has no code signature.")
        } else if run.exitCode == 0 {
            findings.append("Signature present and verifiable by codesign.")
        }
        if output.contains("adhoc") || info["Signature"] == "adhoc" {
            findings.append("Ad-hoc signature: distribution and notarization will fail; use a Developer ID or App Store identity.")
        }
        if let team = info["TeamIdentifier"], team != "not set" {
            findings.append("Team identifier: \(team)")
        } else {
            findings.append("No team identifier embedded.")
        }
        if output.contains("flags=0x10000") || output.contains("runtime") {
            findings.append("Hardened runtime flag detected.")
        }
        var lines = ["Code signing diagnosis for \(trimmed) (exit \(run.exitCode)):"]
        lines += findings.map { "- \($0)" }
        if let authority = info["Authority"] { lines.append("- Authority: \(authority)") }
        if let identifier = info["Identifier"] { lines.append("- Identifier: \(identifier)") }
        if let format = info["Format"] { lines.append("- Format: \(format)") }
        return .structured(["exitCode": .int(Int(run.exitCode)),
                            "teamIdentifier": .string(info["TeamIdentifier"] ?? ""),
                            "authority": .string(info["Authority"] ?? ""),
                            "signed": .bool(!output.contains("code object is not signed"))],
                           summary: lines.joined(separator: "\n"))
    }

    // MARK: - entitlements_diff

    func signingDiffEntitlements(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        guard let oldRaw = call.arguments["oldPath"]?.string, !oldRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let newRaw = call.arguments["newPath"]?.string, !newRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing required parameters: oldPath and newPath")
        }
        func load(_ raw: String) -> [String: Any]? {
            guard let url = resolveFileWritingPath(raw, in: s) else { return nil }
            return signingReadPlistDictionary(at: url)?.dict
        }
        guard let old = load(oldRaw) else { throw MCPToolError("Cannot parse entitlements plist at: \(oldRaw)") }
        guard let new = load(newRaw) else { throw MCPToolError("Cannot parse entitlements plist at: \(newRaw)") }
        let oldKeys = Set(old.keys), newKeys = Set(new.keys)
        let added = newKeys.subtracting(oldKeys).sorted()
        let removed = oldKeys.subtracting(newKeys).sorted()
        var changed: [String] = []
        for key in oldKeys.intersection(newKeys).sorted() {
            let a = "\(old[key] ?? "")", b = "\(new[key] ?? "")"
            if a != b { changed.append("\(key): '\(a.prefix(60))' -> '\(b.prefix(60))'") }
        }
        if added.isEmpty && removed.isEmpty && changed.isEmpty {
            return .structured(["added": .int(0), "removed": .int(0), "changed": .int(0)],
                               summary: "Entitlements are identical.")
        }
        var lines = ["Entitlements diff (\(oldRaw) -> \(newRaw)):"]
        lines += added.map { "- ADDED: \($0)" }
        lines += removed.map { "- REMOVED: \($0)" }
        lines += changed.map { "- CHANGED: \($0)" }
        return .structured(["added": .int(added.count), "removed": .int(removed.count), "changed": .int(changed.count)],
                           summary: lines.joined(separator: "\n"))
    }

    // MARK: - entitlements_manager

    func signingManageEntitlements(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let action = call.arguments["action"]?.string, !action.isEmpty,
              let filePath = call.arguments["filePath"]?.string, !filePath.isEmpty else {
            throw MCPToolError("Missing required parameters: action and filePath")
        }
        guard let fileURL = resolveFileWritingPath(filePath, in: s) else {
            throw MCPToolError("Entitlements file not found at: \(filePath)")
        }
        let rel = fileReadingRelativePath(of: fileURL, in: s)
        switch action.lowercased() {
        case "inspect", "list":
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw MCPToolError("Entitlements file not found at: \(filePath)")
            }
            guard let plist = signingReadPlistDictionary(at: fileURL)?.dict else {
                throw MCPToolError("Invalid property list or cannot parse entitlements at: \(filePath)")
            }
            let keys = plist.keys.sorted().map { "- \($0): \(plist[$0] ?? "")" }
            return .text("Entitlements in '\(filePath)' (\(keys.count) configured):\n" + keys.joined(separator: "\n"))
        case "add_entitlement":
            guard let key = call.arguments["entitlementKey"]?.string, !key.isEmpty else {
                throw MCPToolError("entitlementKey is required for add_entitlement")
            }
            let valStr = call.arguments["value"]?.string ?? "true"
            let boolVal = valStr.lowercased() == "true" || valStr == "1"
            var plistDict = signingReadPlistDictionary(at: fileURL)?.dict ?? [:]
            plistDict[key] = boolVal
            do {
                let updatedData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
                let proposed = String(decoding: updatedData, as: UTF8.self)
                try await commit(MCPChange(tool: call.name, path: fileURL.path, relativePath: rel, original: text(of: fileURL),
                                           proposed: proposed, summary: "Add entitlement '\(key)' = \(boolVal) in \(rel)"),
                                 call: call, session: s)
                return .text("Successfully added entitlement '\(key)' = \(boolVal) in \(filePath)")
            } catch let e as MCPToolError {
                throw e
            } catch {
                throw MCPToolError("Failed to save entitlements: \(error.localizedDescription)")
            }
        case "remove_entitlement":
            guard let key = call.arguments["entitlementKey"]?.string, !key.isEmpty else {
                throw MCPToolError("entitlementKey is required for remove_entitlement")
            }
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  var plistDict = signingReadPlistDictionary(at: fileURL)?.dict else {
                throw MCPToolError("Entitlements file does not exist at: \(filePath)")
            }
            guard plistDict.removeValue(forKey: key) != nil else {
                throw MCPToolError("Entitlement '\(key)' not found in \(filePath)")
            }
            do {
                let updatedData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
                let proposed = String(decoding: updatedData, as: UTF8.self)
                try await commit(MCPChange(tool: call.name, path: fileURL.path, relativePath: rel, original: text(of: fileURL),
                                           proposed: proposed, summary: "Remove entitlement '\(key)' from \(rel)"),
                                 call: call, session: s)
                return .text("Successfully removed entitlement '\(key)' from \(filePath)")
            } catch let e as MCPToolError {
                throw e
            } catch {
                throw MCPToolError("Failed to update entitlements: \(error.localizedDescription)")
            }
        default:
            throw MCPToolError("Unsupported action '\(action)'. Valid: inspect, list, add_entitlement, remove_entitlement")
        }
    }

    // MARK: - info_plist_audit

    func signingAuditInfoPlist(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let plists = signingWorkspaceFiles(in: s) { $0.lastPathComponent == "Info.plist" }
        if plists.isEmpty {
            return .structured(["fileCount": .int(0), "issueCount": .int(0)],
                               summary: "No Info.plist files found in the workspace.")
        }
        let required = ["CFBundleIdentifier", "CFBundleName", "CFBundleShortVersionString", "CFBundleVersion"]
        var bundleIds: [String: [String]] = [:]
        var lines = ["Info.plist audit (\(plists.count) files):"]
        var issueCount = 0
        for url in plists {
            let rel = relative(url.path, in: s)
            guard let plist = signingReadPlistDictionary(at: url)?.dict else {
                lines.append("- \(rel): UNREADABLE plist")
                issueCount += 1
                continue
            }
            var issues: [String] = []
            for key in required where plist[key] == nil { issues.append("missing \(key)") }
            if let v = plist["CFBundleShortVersionString"] as? String,
               v.range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression) == nil {
                issues.append("CFBundleShortVersionString '\(v)' is not x.y[.z]")
            }
            if let bid = plist["CFBundleIdentifier"] as? String { bundleIds[bid, default: []].append(rel) }
            if issues.isEmpty {
                lines.append("- \(rel): OK")
            } else {
                issueCount += issues.count
                lines.append("- \(rel): \(issues.joined(separator: "; "))")
            }
        }
        for (bid, files) in bundleIds where files.count > 1 {
            lines.append("DUPLICATE bundle id '\(bid)' in: \(files.joined(separator: ", "))")
            issueCount += 1
        }
        return .structured(["fileCount": .int(plists.count), "issueCount": .int(issueCount)],
                           summary: lines.joined(separator: "\n"))
    }

    // MARK: - plist_editor

    func signingEditPlist(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let action = call.arguments["action"]?.string, !action.isEmpty,
              let filePath = call.arguments["filePath"]?.string, !filePath.isEmpty else {
            throw MCPToolError("Missing required parameters: action and filePath")
        }
        guard let fileURL = resolveFileWritingPath(filePath, in: s),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MCPToolError("Plist file does not exist at path: \(filePath)")
        }
        guard let loaded = signingReadPlistDictionary(at: fileURL) else {
            throw MCPToolError("File at \(filePath) is not a dictionary-rooted property list.")
        }
        var plistDict = loaded.dict
        let rel = fileReadingRelativePath(of: fileURL, in: s)
        switch action.lowercased() {
        case "list_keys":
            let keys = plistDict.keys.sorted()
            return .text("Plist contains \(keys.count) keys:\n" + keys.joined(separator: "\n"))
        case "read":
            guard let key = call.arguments["key"]?.string, !key.isEmpty else {
                throw MCPToolError("key parameter is required for read")
            }
            if let val = plistDict[key] {
                return .text("\(key) = \(String(describing: val))")
            }
            throw MCPToolError("Key '\(key)' not found in \(filePath)")
        case "set":
            guard let key = call.arguments["key"]?.string, !key.isEmpty else {
                throw MCPToolError("key parameter is required for set")
            }
            let valStr = call.arguments["value"]?.string ?? ""
            let vType = (call.arguments["valueType"]?.string ?? "string").lowercased()
            if vType == "boolean" {
                plistDict[key] = valStr.lowercased() == "true" || valStr == "1"
            } else if vType == "integer" {
                plistDict[key] = Int(valStr) ?? 0
            } else {
                plistDict[key] = valStr
            }
            try await signingWritePlist(plistDict, format: loaded.format, to: fileURL, relativePath: rel,
                                        summary: "Set '\(key)' = \(valStr) in \(rel)", call: call, session: s)
            return .text("Successfully set '\(key)' = \(valStr) in \(filePath)")
        case "delete":
            guard let key = call.arguments["key"]?.string, !key.isEmpty else {
                throw MCPToolError("key parameter is required for delete")
            }
            guard plistDict.removeValue(forKey: key) != nil else {
                throw MCPToolError("Key '\(key)' not found in \(filePath)")
            }
            try await signingWritePlist(plistDict, format: loaded.format, to: fileURL, relativePath: rel,
                                        summary: "Remove key '\(key)' from \(rel)", call: call, session: s)
            return .text("Successfully removed key '\(key)' from \(filePath)")
        default:
            throw MCPToolError("Unsupported action '\(action)'. Valid: read, set, delete, list_keys")
        }
    }

    /// Writes a plist dictionary back in its source format: XML goes
    /// through `commit()` (text); a binary source goes through
    /// `approveFileWritingChange` + a direct `Data` write, the
    /// `json_to_plist` shape, because `commit()` cannot write bytes.
    func signingWritePlist(_ dict: [String: Any], format: PropertyListSerialization.PropertyListFormat,
                           to url: URL, relativePath rel: String, summary: String,
                           call: MCPToolCall, session s: WorkspaceSession) async throws {
        let data: Data
        do {
            data = try PropertyListSerialization.data(fromPropertyList: dict, format: format, options: 0)
        } catch {
            throw MCPToolError("Error processing plist: \(error.localizedDescription)")
        }
        if format == .binary {
            try await approveFileWritingChange(tool: call.name, path: url, relativePath: rel, original: text(of: url),
                                               summary: summary, call: call)
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                throw MCPToolError("Error processing plist: \(error.localizedDescription)")
            }
            noteFileWritingChanged(url, in: s)
        } else {
            try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: text(of: url),
                                       proposed: String(decoding: data, as: UTF8.self), summary: summary),
                             call: call, session: s)
        }
    }

    // MARK: - project_entitlements

    func signingProjectEntitlements(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let explicitPath = call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        var fileURLs: [URL] = []
        if let explicitPath, !explicitPath.isEmpty {
            guard let resolved = resolveFileWritingPath(explicitPath, in: s) else {
                throw MCPToolError("Path '\(explicitPath)' is outside the workspace or contains '..'.")
            }
            guard FileManager.default.fileExists(atPath: resolved.path) else {
                throw MCPToolError("Entitlements file not found at '\(explicitPath)'.")
            }
            fileURLs = [resolved]
        } else {
            fileURLs = signingWorkspaceFiles(in: s) { $0.pathExtension == "entitlements" }
            if fileURLs.isEmpty {
                throw MCPToolError("No .entitlements files found in the workspace.")
            }
        }
        var allKeys: [String] = []
        var summaries: [String] = []
        for url in fileURLs {
            guard (try? Data(contentsOf: url)) != nil else {
                throw MCPToolError("Failed to read entitlements file '\(url.lastPathComponent)'.")
            }
            guard let dict = signingReadPlistDictionary(at: url)?.dict else {
                throw MCPToolError("Entitlements file '\(url.lastPathComponent)' is not a valid property list dictionary.")
            }
            let keys = dict.keys.sorted()
            allKeys += keys
            let entries = keys.map { key in "\(key) = \(signingPlistString(dict[key]))" }.joined(separator: "; ")
            summaries.append("\(url.lastPathComponent): \(entries.isEmpty ? "(no keys)" : entries)")
        }
        let uniqueKeys = Array(Set(allKeys)).sorted()
        return .structured(["files": .string(fileURLs.map(\.lastPathComponent).joined(separator: ",")),
                            "keys": .string(uniqueKeys.joined(separator: ",")),
                            "count": .int(uniqueKeys.count)],
                           summary: summaries.joined(separator: "\n"))
    }

    // MARK: - project_info_plist

    func signingEditProjectInfoPlist(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let action = (call.arguments["action"]?.string ?? "get").lowercased()
        guard action == "get" || action == "set" || action == "delete" else {
            throw MCPToolError("Invalid action '\(action)'. Expected get, set, or delete.")
        }
        let key = call.arguments["key"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = call.arguments["value"]?.string
        let explicitPath = call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        let plistURL: URL
        if let explicitPath, !explicitPath.isEmpty {
            guard let resolved = resolveFileWritingPath(explicitPath, in: s) else {
                throw MCPToolError("Path '\(explicitPath)' is outside the workspace or contains '..'.")
            }
            plistURL = resolved
        } else {
            guard let found = signingFindInfoPlist(in: s) else {
                throw MCPToolError("No Info.plist found in the workspace.")
            }
            plistURL = found
        }
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            throw MCPToolError("Info.plist not found at '\(plistURL.lastPathComponent)'.")
        }
        guard var dict = signingReadPlistDictionary(at: plistURL)?.dict else {
            throw MCPToolError("Info.plist at '\(plistURL.lastPathComponent)' is not a valid property list dictionary.")
        }
        let rel = fileReadingRelativePath(of: plistURL, in: s)
        switch action {
        case "get":
            if let key, !key.isEmpty {
                guard let found = dict[key] else {
                    throw MCPToolError("Key '\(key)' not found in Info.plist.")
                }
                return .structured(["key": .string(key), "value": .string(signingPlistString(found)),
                                    "file": .string(plistURL.lastPathComponent)],
                                   summary: "Info.plist \(key) = \(signingPlistString(found))")
            }
            let keys = dict.keys.sorted()
            let entries = keys.map { "\($0) = \(signingPlistString(dict[$0]))" }.joined(separator: "\n")
            return .structured(["keys": .string(keys.joined(separator: ",")), "count": .int(keys.count),
                                "file": .string(plistURL.lastPathComponent)],
                               summary: "Info.plist has \(keys.count) key(s):\n\(entries)")
        case "set":
            guard let key, !key.isEmpty else { throw MCPToolError("Missing required parameter: key for action=set") }
            guard let value else { throw MCPToolError("Missing required parameter: value for action=set") }
            let before = dict[key]
            dict[key] = signingPlistValue(from: value)
            guard let updatedData = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) else {
                throw MCPToolError("Failed to write Info.plist.")
            }
            do {
                try await commit(MCPChange(tool: call.name, path: plistURL.path, relativePath: rel, original: text(of: plistURL),
                                           proposed: String(decoding: updatedData, as: UTF8.self),
                                           summary: "Set Info.plist \(key) = \(value) in \(rel)"),
                                 call: call, session: s)
            } catch let e as MCPToolError {
                // A review rejection must surface verbatim; any other
                // write failure keeps Legacy's message.
                throw MCPToolError(e.message == MCPServer.rejectedMessage ? e.message : "Failed to write Info.plist.")
            }
            guard let verify = signingReadPlistDictionary(at: plistURL)?.dict,
                  let written = verify[key],
                  signingPlistString(written) == signingPlistString(signingPlistValue(from: value)) else {
                throw MCPToolError("Verification failed: key '\(key)' was not written to Info.plist.")
            }
            return .structured(["key": .string(key), "value": .string(value), "file": .string(plistURL.lastPathComponent)],
                               summary: "Set Info.plist \(key) = \(value) (was: \(signingPlistString(before))).")
        case "delete":
            guard let key, !key.isEmpty else { throw MCPToolError("Missing required parameter: key for action=delete") }
            guard dict[key] != nil else { throw MCPToolError("Key '\(key)' not found in Info.plist.") }
            dict.removeValue(forKey: key)
            guard let updatedData = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) else {
                throw MCPToolError("Failed to write Info.plist.")
            }
            do {
                try await commit(MCPChange(tool: call.name, path: plistURL.path, relativePath: rel, original: text(of: plistURL),
                                           proposed: String(decoding: updatedData, as: UTF8.self),
                                           summary: "Delete Info.plist key '\(key)' in \(rel)"),
                                 call: call, session: s)
            } catch let e as MCPToolError {
                throw MCPToolError(e.message == MCPServer.rejectedMessage ? e.message : "Failed to write Info.plist.")
            }
            guard let verify = signingReadPlistDictionary(at: plistURL)?.dict, verify[key] == nil else {
                throw MCPToolError("Verification failed: key '\(key)' still present in Info.plist.")
            }
            return .structured(["key": .string(key), "file": .string(plistURL.lastPathComponent)],
                               summary: "Deleted Info.plist key '\(key)'.")
        default:
            throw MCPToolError("Invalid action '\(action)'.")
        }
    }

    // MARK: - project_signing

    func signingCheckProjectSigning(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let configuration = (call.arguments["configuration"]?.string ?? "Debug").trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = call.string("scheme")
        guard !configuration.isEmpty else { throw MCPToolError("Missing required parameter: configuration") }
        guard s.model.kind != .package, !s.model.projects.isEmpty else {
            throw MCPToolError("No .xcodeproj or .xcworkspace found at the top level of the workspace.")
        }
        let projects = s.model.projects.sorted { $0.key < $1.key }
        guard let (path, proj) = projects.first else {
            throw MCPToolError("No .xcodeproj or .xcworkspace found at the top level of the workspace.")
        }
        let xcodeproj = URL(fileURLWithPath: path)
        var builder = ProjectSettingsBuilder(proj: proj, xcodeprojURL: xcodeproj)
        builder.developerDirectory = Workspace.activeDeveloperDirectory()
        if let dev = builder.developerDirectory {
            let catalog = SDKCatalog(developerDirectory: dev)
            builder.sdkLookup = { catalog.lookup($0) }
        }
        // Legacy's scheme selected the target implicitly through
        // xcodebuild; here a scheme naming a target selects it,
        // otherwise the first target is used (the `build_settings`
        // tool's rule).
        let target = scheme.flatMap { name in proj.targets.first { $0.string("name") == name }?.string("name") }
            ?? proj.targets.first?.string("name")
        let resolved: ProjectSettingsBuilder.Resolved
        do {
            resolved = try builder.resolve(target: target, configuration: configuration)
        } catch {
            throw MCPToolError("cannot resolve the settings of \(target ?? "the project") (\(configuration)): \(error)")
        }
        let settings = resolved.settings
        let profiles = signingInstalledProfileNames()
        let summary = """
        Signing for configuration '\(configuration)':
        CODE_SIGN_STYLE = \(settings["CODE_SIGN_STYLE"].isEmpty ? "(not set)" : settings["CODE_SIGN_STYLE"])
        DEVELOPMENT_TEAM = \(settings["DEVELOPMENT_TEAM"].isEmpty ? "(not set)" : settings["DEVELOPMENT_TEAM"])
        PRODUCT_BUNDLE_IDENTIFIER = \(settings["PRODUCT_BUNDLE_IDENTIFIER"].isEmpty ? "(not set)" : settings["PRODUCT_BUNDLE_IDENTIFIER"])
        CODE_SIGN_IDENTITY = \(settings["CODE_SIGN_IDENTITY"].isEmpty ? "(not set)" : settings["CODE_SIGN_IDENTITY"])
        PROVISIONING_PROFILE_SPECIFIER = \(settings["PROVISIONING_PROFILE_SPECIFIER"].isEmpty ? "(not set)" : settings["PROVISIONING_PROFILE_SPECIFIER"])
        Provisioning profiles installed: \(profiles.count)
        """
        var data: [String: AnyJSON] = [
            "configuration": .string(configuration),
            "codeSignStyle": .string(settings["CODE_SIGN_STYLE"]),
            "developmentTeam": .string(settings["DEVELOPMENT_TEAM"]),
            "bundleId": .string(settings["PRODUCT_BUNDLE_IDENTIFIER"]),
            "codeSignIdentity": .string(settings["CODE_SIGN_IDENTITY"]),
            "provisioningProfileSpecifier": .string(settings["PROVISIONING_PROFILE_SPECIFIER"]),
            "provisioningProfileCount": .int(profiles.count),
            "provisioningProfiles": .string(profiles.joined(separator: ",")),
        ]
        if let scheme, !scheme.isEmpty { data["scheme"] = .string(scheme) }
        return .structured(data, summary: summary)
    }

    // MARK: - provisioning_check

    func signingCheckProvisioning(_ call: MCPToolCall) async throws -> MCPToolResult {
        let bundleId = call.arguments["bundleId"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/security") else {
            throw MCPToolError("security tool not found at /usr/bin/security.")
        }
        let profilesDir = signingProfilesDirectory()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: profilesDir.path, isDirectory: &isDir), isDir.boolValue else {
            throw MCPToolError("No provisioning profiles directory found at ~/Library/MobileDevice/Provisioning Profiles. No profiles are installed.")
        }
        let contents = (try? FileManager.default.contentsOfDirectory(at: profilesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let profiles = contents.filter { $0.pathExtension == "mobileprovision" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !profiles.isEmpty else {
            throw MCPToolError("No .mobileprovision files found in ~/Library/MobileDevice/Provisioning Profiles.")
        }
        var lines: [String] = []
        var expiredCount = 0
        var expiringCount = 0
        var matchCount = 0
        var mismatchCount = 0
        let now = Date()
        let expiringThreshold = now.addingTimeInterval(30 * 24 * 60 * 60)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        for profileURL in profiles {
            let decoded = signingDecodeProfile(at: profileURL)
            guard let plist = decoded.dict else {
                lines.append("\(profileURL.lastPathComponent) - could not decode: \(decoded.stderr.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300))")
                continue
            }
            let name = plist["Name"] as? String ?? profileURL.lastPathComponent
            let team = plist["TeamName"] as? String ?? "(unknown team)"
            let expiration = plist["ExpirationDate"] as? Date
            let expirationText = expiration.map { dateFormatter.string(from: $0) } ?? "(unknown)"
            var status = "valid"
            if let expiration {
                if expiration < now {
                    status = "EXPIRED"
                    expiredCount += 1
                } else if expiration < expiringThreshold {
                    status = "expiring soon"
                    expiringCount += 1
                }
            }
            var appId = "(unknown)"
            if let entitlements = plist["Entitlements"] as? [String: Any],
               let applicationIdentifier = entitlements["application-identifier"] as? String {
                appId = applicationIdentifier
            } else if let appIDName = plist["AppIDName"] as? String {
                appId = appIDName
            }
            var comparison = "no bundleId given"
            if let bundleId, !bundleId.isEmpty {
                let bundlePart: String
                if let dot = appId.firstIndex(of: ".") {
                    bundlePart = String(appId[appId.index(after: dot)...])
                } else {
                    bundlePart = appId
                }
                if bundlePart == bundleId {
                    comparison = "matches \(bundleId)"
                    matchCount += 1
                } else if bundlePart == "*" {
                    comparison = "wildcard - covers \(bundleId)"
                    matchCount += 1
                } else {
                    comparison = "MISMATCH (profile App ID bundle: \(bundlePart))"
                    mismatchCount += 1
                }
            }
            lines.append("\(name) - team: \(team) - AppID: \(appId) - expires: \(expirationText) - \(status) - \(comparison)")
        }
        var header = "Provisioning profiles: \(profiles.count), expired: \(expiredCount), expiring within 30 days: \(expiringCount)"
        if let bundleId, !bundleId.isEmpty {
            header += ", bundle \(bundleId): \(matchCount) match(es), \(mismatchCount) mismatch(es)"
        }
        return .structured(["profile_count": .int(profiles.count), "expired_count": .int(expiredCount),
                            "expiring_count": .int(expiringCount), "match_count": .int(matchCount),
                            "mismatch_count": .int(mismatchCount), "bundle_id": .string(bundleId ?? "")],
                           summary: header + "\n" + lines.joined(separator: "\n"))
    }

    // MARK: - provisioning_profile_reader

    func signingReadProvisioningProfile(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let path = call.arguments["path"]?.string, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing required parameter: path")
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        // Profiles live outside any workspace (~/Library/MobileDevice/
        // Provisioning Profiles), so an absolute path is used as-is —
        // the same read-only exception Wave 6 made for
        // `test_coverage_reporter`'s explicit report path. A relative
        // path resolves against the workspace root and must stay
        // inside it.
        let resolvedURL: URL
        if trimmed.hasPrefix("/") {
            resolvedURL = URL(fileURLWithPath: trimmed)
        } else {
            guard let url = resolveFileWritingPath(trimmed, in: s) else {
                throw MCPToolError("Provisioning profile not found at: \(trimmed)")
            }
            resolvedURL = url
        }
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            throw MCPToolError("Provisioning profile not found at: \(trimmed)")
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/security") else {
            throw MCPToolError("Failed to execute security cms -D: /usr/bin/security is not available on this platform.")
        }
        let decoded = signingDecodeProfile(at: resolvedURL)
        guard let plist = decoded.dict else {
            throw MCPToolError("Failed to decode XML property list from provisioning profile.")
        }
        let name = plist["Name"] as? String ?? "Unknown"
        let appIDName = plist["AppIDName"] as? String ?? "Unknown"
        let teamName = plist["TeamName"] as? String ?? "Unknown"
        let teamID = (plist["TeamIdentifier"] as? [String])?.first ?? "Unknown"
        let expiration = plist["ExpirationDate"] as? Date
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        var report = "### Provisioning Profile Summary (`\(resolvedURL.lastPathComponent)`):\n\n"
        report += "- **Profile Name**: `\(name)`\n"
        report += "- **Team**: `\(teamName)` (\(teamID))\n"
        report += "- **App ID Name**: `\(appIDName)`\n"
        if let exp = expiration {
            report += "- **Expiration Date**: `\(ISO8601DateFormatter().string(from: exp))`\n"
        }
        report += "\n#### Entitlements Included (\(entitlements.count)):\n"
        for (k, v) in entitlements.sorted(by: { $0.key < $1.key }) {
            report += "- **\(k)**: `\(v)`\n"
        }
        return .text(report)
    }

    // MARK: - signing_certificate_inspector

    func signingInspectSigningCertificates(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/security") else {
            throw MCPToolError("Failed to execute security find-identity: /usr/bin/security is not available on this platform.")
        }
        guard let run = Self.terminalRunFixed("/usr/bin/security", ["find-identity", "-p", "codesigning", "-v"], timeout: 60) else {
            throw MCPToolError("Failed to execute security find-identity: could not launch /usr/bin/security")
        }
        let output = (run.stdout + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty {
            return .text("No valid code-signing identities found in macOS Keychain.")
        }
        var report = "### Available Code Signing Certificates:\n\n"
        for line in output.components(separatedBy: .newlines) {
            report += "- `\(line.trimmingCharacters(in: .whitespaces))`\n"
        }
        return .text(report)
    }
}
