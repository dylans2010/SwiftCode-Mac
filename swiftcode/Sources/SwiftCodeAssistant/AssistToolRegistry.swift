// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/AssistToolRegistry.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeAssistant (`swiftcode/Sources/SwiftCodeAssistant/AssistToolRegistry.swift`).
// MOVED here by MCP-DEP (2026-11-06, decision (b) in staging-wire/mcp-dep/DISPOSITIONS.md):
// SwiftCodeAssistant cannot import SwiftCodeMCP (MCP depends on Assistant — a reverse
// dep would be a cycle), and the registry's whole dependency closure lives here
// (AssistTool in this target; ToolCapability in AssistToolRouter.swift;
// ToolValidationResult in AssistErrorRecoveryEngine.swift). MCP keeps using it
// through its own import of this target.
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - dynamic register/unregister
//   - tool health tracking (ToolHealth/ToolHealthStatus)
//   - read-only result caching (get/setCachedResult)
//   - schema caching (cachedSchema/invalidateSchemaCache)
//   - capability index / toolsForCapability
// ADAPTATIONS:
//   - MOVED 2026-11-06 (MCP-DEP): file moved SwiftCodeMCP -> SwiftCodeAssistant;
//     the cross-target import was dropped (same target now); `registerAllTools()`
//     removed — it listed ~291 concrete tool types, 274 of which exist nowhere
//     in the tree yet and 17 of which live in SwiftCodeMCP (unimportable from
//     here). Enrolment is split by module: MCP tools enrol from
//     SwiftCodeMCP/AssistToolRegistry+MCPTools.swift; each further tool enrols
//     via register(_:) as it lands. The registry mechanics are unchanged.
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - AssistAccessLevelAuditTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistAccessLevelAuditTool.swift`)
//   - AssistAccessibilityAuditScannerTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistAccessibilityAuditScannerTool.swift`)
//   - AssistAccessibilityAuditTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistAccessibilityAuditTool.swift`)
//   - AssistApiDocsCoverageTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistApiDocsCoverageTool.swift`)
//   - AssistApiEndpointAuditTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistApiEndpointAuditTool.swift`)
//   - AssistApiSurfaceExtractTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistApiSurfaceExtractTool.swift`)
//   - AssistAppendFileTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistAppendFileTool.swift`)
//   - AssistArtboardCreateTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistArtboardCreateTool.swift`)
//   - AssistArtboardDeleteTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistArtboardDeleteTool.swift`)
//   - AssistArtboardGetTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistArtboardGetTool.swift`)
//   - AssistArtboardListTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistArtboardListTool.swift`)
//   - AssistArtboardRunAppTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistArtboardRunAppTool.swift`)
//   - AssistArtboardUpdateTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistArtboardUpdateTool.swift`)
//   - AssistAssetCatalogListTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistAssetCatalogListTool.swift`)
//   - AssistAssetCatalogTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistAssetCatalogTool.swift`)
//   - AssistAssetImageAddTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistAssetImageAddTool.swift`)
//   - AssistAutoFixErrorsTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistAutoFixErrorsTool.swift`)
//   - AssistAutomatedRepairEngine — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistAutomatedRepairEngine.swift`)
//   - AssistAutonomousReviewEngine — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistAutonomousReviewEngine.swift`)
//   - AssistBatchRenameFilesTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistDataMutationTools.swift`)
//   - AssistBinaryPlistConverterTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistBinaryPlistConverterTool.swift`)
//   - AssistBinarySizeReportTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistBinarySizeReportTool.swift`)
//   - AssistBreakdownTaskTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistBreakdownTaskTool.swift`)
//   - AssistBuildConfigurationListTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistBuildConfigurationListTool.swift`)
//   - AssistBuildLogAnalyzeTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistBuildLogAnalyzeTool.swift`)
//   - AssistBuildPhaseScriptsListTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistBuildPhaseScriptsListTool.swift`)
//   - AssistBuildProjectTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistBuildProjectTool.swift`)
//   - AssistBuildSettingsDiffTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistBuildSettingsDiffTool.swift`)
//   - AssistBuildSystemDetectTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistBuildSystemDetectTool.swift`)
//   - AssistBundleResourceAuditorTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistBundleResourceAuditorTool.swift`)
//   - AssistCallHierarchyTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistCallHierarchyTool.swift`)
//   - AssistCarthageCartfileInspectorTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistCarthageCartfileInspectorTool.swift`)
//   - AssistChangeDirectoryTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistChangeDirectoryTool.swift`)
//   - AssistChangeImpactEstimateTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistChangeImpactEstimateTool.swift`)
//   - AssistClearMemoryTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistClearMemoryTool.swift`)
//   - AssistClipboardManagerTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistClipboardManagerTool.swift`)
//   - AssistCodeCommentExtractTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistCodeCommentExtractTool.swift`)
//   - AssistCodeMetricsTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistCodeMetricsTool.swift`)
//   - AssistCodeMutationEngine — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistCodeMutationEngine.swift`)
//   - AssistCodeSigningDiagnoseTool — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/Tools/AssistCodeSigningDiagnoseTool.swift`)
//   - ... and 236 more (full list in assist/DISPOSITIONS.md).
// WIRING / REGISTRATION: Dynamic registry: MCPServer tools catalogue stays the live registry until wired; instantiate AssistToolRegistry.shared and register legacy tools as they land; enrolment is split by module (see init()).

import Foundation

public enum ToolHealthStatus: String, Codable, Sendable {
    case registered
    case available
    case temporarilyUnavailable
    case disabled
    case error
}

public struct ToolHealth: Codable, Sendable {
    public let toolId: String
    public var status: ToolHealthStatus
    public var lastError: String?
    public let registeredAt: Date
    public var lastUsedAt: Date?
    public var useCount: Int

    public init(toolId: String, status: ToolHealthStatus = .registered, lastError: String? = nil) {
        self.toolId = toolId
        self.status = status
        self.lastError = lastError
        self.registeredAt = Date()
        self.lastUsedAt = nil
        self.useCount = 0
    }
}

@MainActor
public final class AssistToolRegistry {
    public static let shared = AssistToolRegistry()

    private var tools: [String: AssistTool] = [:]
    private var health: [String: ToolHealth] = [:]
    private var capabilityIndex: [ToolCapability: [String]] = [:]
    private var schemaCache: [String: String] = [:]
    private var registryVersion: Int = 0

    // Read-only result cache for runtime idempotency
    private var readOnlyResultCache: [String: (result: String, timestamp: Date)] = [:]
    private var lastMutationTimestamp: Date = Date.distantPast

    public func invalidateReadOnlyCache() {
        readOnlyResultCache.removeAll()
        lastMutationTimestamp = Date()
    }

    public func getCachedResult(semanticKey: String) -> String? {
        guard let cached = readOnlyResultCache[semanticKey] else { return nil }
        if cached.timestamp >= lastMutationTimestamp {
            return cached.result
        } else {
            readOnlyResultCache.removeValue(forKey: semanticKey)
            return nil
        }
    }

    public func setCachedResult(_ result: String, for semanticKey: String) {
        readOnlyResultCache[semanticKey] = (result: result, timestamp: Date())
    }

    /// Assistant-side tools enrol here at `init()` so both a fresh
    /// `AssistToolRegistry()` and `.shared` contain them (the
    /// `AssistRuntimeTestSuite` constructs fresh registries and resolves
    /// tools off `.shared`). MCP-defined tools still enrol separately in
    /// `AssistToolRegistry+MCPTools.swift` (`registerMCPTools()`, called
    /// once at MCP startup), because this target cannot import SwiftCodeMCP.
    /// Enrolment lives with the tools: each further Assistant-side tool
    /// registers itself in `registerAssistantTools()` (see
    /// `AssistToolRegistry+AssistantTools.swift`) as it lands.
    public init() {
        registerAssistantTools()
    }

    public var version: Int { registryVersion }
    private var cachedToolSchemas: [[String: Any]]?

    public func register(_ tool: AssistTool) {
        // Never silently overwrite on a duplicate ID: the first registration
        // wins and the collision is logged, so a duplicate is loud, not a
        // last-wins surprise.
        if tools[tool.id] != nil {
            print("[AssistToolRegistry] Duplicate tool ID '\(tool.id)' — keeping the first registration.")
            return
        }
        tools[tool.id] = tool
        health[tool.id] = ToolHealth(toolId: tool.id, status: .available)
        rebuildCapabilityIndex()
        schemaCache.removeAll()
        cachedToolSchemas = nil
        registryVersion += 1
    }

    public func unregister(_ toolId: String) {
        tools.removeValue(forKey: toolId)
        health.removeValue(forKey: toolId)
        rebuildCapabilityIndex()
        schemaCache.removeAll()
        cachedToolSchemas = nil
        registryVersion += 1
    }

    private let toolAliases: [String: String] = [
        "git": "version_control_operator",
        "git_status": "version_control_operator",
        "git_diff": "version_control_operator",
        "git_commit": "version_control_operator",
        "git_branch": "version_control_operator",
        "git_rollback": "version_control_operator",
        "git_tool": "version_control_operator",
        "version_control": "version_control_operator",
        "build": "project_build",
        "build_project": "project_build",
        "run_build": "project_build",
        "xcodebuild": "project_build",
        "test": "project_test",
        "run_tests": "project_test",
        "open_finder": "open_in_finder",
        "open_in_finder": "open_in_finder",
        "reveal_finder": "reveal_in_finder",
        "reveal_in_finder": "reveal_in_finder",
        "show_in_finder": "reveal_in_finder",
        "write_file": "file_write",
        "create_file": "file_create",
        "read_file": "file_read",
        "view_file": "file_read",
        "delete_file": "file_delete",
        "move_file": "file_move",
        "copy_file": "file_copy",
        "rename_file": "file_rename",
        "edit_file": "code_replace",
        "replace_in_file": "code_replace",
        "insert_code_block": "code_insert",
        "insert_code": "code_insert",
        "run_command": "use_terminal",
        "terminal_command": "use_terminal",
        "execute_command": "use_terminal",
        "bash": "use_terminal",
        "sh": "use_terminal",
        "zsh": "use_terminal",
        "list_dir": "dir_read",
        "list_directory": "dir_read",
        "directory_read": "dir_read",
        "search_dir": "search_text",
        "search_directory": "search_text",
        "find_file": "search_text",
        "search": "search_text",
        "create_directory": "dir_create",
        "make_directory": "dir_create",
        "directory_create": "dir_create",
        "delete_directory": "dir_delete",
        "remove_directory": "dir_delete",
        "directory_delete": "dir_delete",
        "use_workers": "use_workers",
        "useworkers": "use_workers",
        "workflow": "use_workers",
        "plan_askuser": "plan-AskUser",
        "plan_ask_user": "plan-AskUser",
        "ask_user": "plan-AskUser",
        "planaskuser": "plan-AskUser",
        "report_to_user": "report_to_user",
        "reporttouser": "report_to_user",
        "task_complete": "report_to_user",
        "task_completion": "report_to_user",
        "asset_catalog": "asset_catalog_manager",
        "swift_package": "swift_package_manager",
        "spm": "swift_package_manager",
        "plist": "plist_editor",
        "metrics": "code_metrics_analyzer",
        "localization": "localization_manager",
        "memory_leak": "memory_leak_detector",
        "dead_code": "dead_code_eliminator",
        "docstring": "docstring_generator",
        "entitlements": "entitlements_manager",
        "snippet": "code_snippet_manager",
        "security_audit": "security_audit_scanner",
        "migration_advisor": "swift_migration_advisor",
        "git_stash": "git_stash_operator",
        "xcode_scheme": "xcode_scheme_manager",
        "memory_save": "save_to_memory",
        "save_memory": "save_to_memory",
        "memory_view": "view_memory",
        "memory_manage": "manage_memory",
        "conversation_context": "conversation_context_manager",
        "ast_inspector": "swift_ast_inspector",
        "build_settings": "xcode_build_settings_inspector",
        "symbol_graph": "symbol_reference_graph",
        "xcresult": "xcresult_parser",
        "device_destinations": "xcode_device_destination_finder",
        "simulator": "simulator_controller",
        "git_blame": "git_blame_inspector",
        "git_branches": "git_branch_manager",
        "git_log": "git_log_viewer",
        "git_conflict": "git_conflict_resolver",
        "swift_format": "swift_format_lint",
        "todo_scanner": "todo_fixme_scanner",
        "unused_imports": "unused_imports_detector",
        "bundle_auditor": "bundle_resource_auditor",
        "core_data_inspector": "core_data_model_inspector",
        "swift_data_schema": "swift_data_schema_auditor",
        "privacy_manifest": "privacy_manifest_auditor",
        "icon_generator": "icon_generator_tool",
        "colorset": "colorset_builder",
        "string_catalog": "string_catalog_migrator",
        "test_coverage": "test_coverage_reporter",
        "spm_tree": "spm_dependency_tree",
        "podfile": "podfile_inspector",
        "cartfile": "carthage_cartfile_inspector",
        "macho_analyzer": "mach_o_binary_analyzer",
        "framework_linker": "framework_linker_auditor",
        "signing_certificate": "signing_certificate_inspector",
        "provisioning_profile": "provisioning_profile_reader",
        "network_security": "network_security_auditor",
        "a11y_scanner": "accessibility_audit_scanner",
        "concurrency_analyzer": "swift_concurrency_analyzer",
        "regex_replace": "regex_replace_in_files",
        "checksum_verifier": "file_checksum_verifier",
        "binary_plist": "binary_plist_converter",
        "json_validator": "json_validator_tool",
        "yaml_parser": "yaml_parser_tool",
        "env_manager": "environment_variable_manager",
        "clipboard": "clipboard_manager_tool",
        "reverse": "reverse_analyze",
        "reverse_analyze": "reverse_analyze",
        "process_monitor": "process_monitor_tool",
        "disk_space": "disk_space_analyzer",
        "system_notification": "system_notification_tool"
    ]

    public func getTool(_ id: String) -> AssistTool? {
        if let direct = tools[id] {
            return direct
        }
        var cleaned = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned.hasPrefix("muse.") {
            cleaned = String(cleaned.dropFirst(5))
        } else if cleaned.hasPrefix("muse_") {
            cleaned = String(cleaned.dropFirst(5))
        }
        cleaned = cleaned.replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ".", with: "_")

        if let directNorm = tools[cleaned] {
            return directNorm
        }

        if let match = tools.values.first(where: {
            $0.id.caseInsensitiveCompare(id) == .orderedSame ||
            $0.id.lowercased().replacingOccurrences(of: "-", with: "_") == cleaned
        }) {
            return match
        }

        if let alias = toolAliases[cleaned], let target = getTool(alias) {
            return target
        }
        return nil
    }

    public func resolve(toolId: String) -> AssistTool? {
        return getTool(toolId)
    }

    public var allTools: [AssistTool] {
        return Array(tools.values).sorted(by: { $0.id < $1.id })
    }

    public func getToolSchemas() -> [[String: Any]] {
        if let cached = cachedToolSchemas {
            return cached
        }
        let schemas: [[String: Any]] = allTools.map { tool in
            var schemaDict: [String: Any] = [
                "name": tool.id,
                "description": tool.description
            ]
            if let schemaData = try? JSONEncoder().encode(tool.parametersSchema),
               let paramObj = try? JSONSerialization.jsonObject(with: schemaData) as? [String: Any] {
                schemaDict["parameters"] = paramObj
            }
            return schemaDict
        }
        cachedToolSchemas = schemas
        return schemas
    }

    public func toolsForCapability(_ capability: ToolCapability) -> [AssistTool] {
        let ids = capabilityIndex[capability] ?? []
        return ids.compactMap { tools[$0] }
    }

    public var capabilityMap: [ToolCapability: [String]] {
        return capabilityIndex
    }

    public var compactCapabilityRepresentation: [String: [String]] {
        var result: [String: [String]] = [:]
        for (capability, ids) in capabilityIndex {
            result[capability.rawValue] = ids
        }
        return result
    }

    public func getHealth(_ toolId: String) -> ToolHealth? {
        return health[toolId]
    }

    public var allHealth: [ToolHealth] {
        return health.values.sorted { $0.toolId < $1.toolId }
    }

    public func markUsed(_ toolId: String) {
        health[toolId]?.lastUsedAt = Date()
        health[toolId]?.useCount += 1
    }

    public func markError(_ toolId: String, error: String) {
        health[toolId]?.status = .error
        health[toolId]?.lastError = error
    }

    public func markUnavailable(_ toolId: String) {
        health[toolId]?.status = .temporarilyUnavailable
    }

    public func markAvailable(_ toolId: String) {
        health[toolId]?.status = .available
        health[toolId]?.lastError = nil
    }

    public func disable(_ toolId: String) {
        health[toolId]?.status = .disabled
    }

    public func enable(_ toolId: String) {
        health[toolId]?.status = .available
    }

    public func validate(toolId: String, arguments: [String: Any]) -> ToolValidationResult {
        let normalizedId = toolId.lowercased().replacingOccurrences(of: "-", with: "_")
        let effectiveToolId = toolAliases[normalizedId] ?? (tools[toolId] != nil ? toolId : normalizedId)

        guard let tool = getTool(effectiveToolId) else {
            return ToolValidationResult(isValid: false, issue: "Tool '\(toolId)' is not registered")
        }

        if let toolHealth = health[tool.id], toolHealth.status == .disabled {
            return ToolValidationResult(isValid: false, issue: "Tool '\(toolId)' is disabled")
        }

        if let toolHealth = health[tool.id], toolHealth.status == .temporarilyUnavailable {
            return ToolValidationResult(isValid: false, issue: "Tool '\(toolId)' is temporarily unavailable")
        }

        var normalizedArgs = arguments

        // Common parameter aliases
        if normalizedArgs["path"] == nil {
            if let p = normalizedArgs["filePath"] ?? normalizedArgs["file_path"] ?? normalizedArgs["targetFile"] ?? normalizedArgs["file"] {
                normalizedArgs["path"] = p
            }
        }
        if normalizedArgs["content"] == nil {
            if let c = normalizedArgs["fileContent"] ?? normalizedArgs["file_content"] ?? normalizedArgs["code"] ?? normalizedArgs["data"] {
                normalizedArgs["content"] = c
            }
        }
        if normalizedArgs["target"] == nil {
            if let t = normalizedArgs["targetContent"] ?? normalizedArgs["old_string"] ?? normalizedArgs["old_str"] ?? normalizedArgs["find"] {
                normalizedArgs["target"] = t
            }
        }
        if normalizedArgs["replacement"] == nil {
            if let r = normalizedArgs["replacementContent"] ?? normalizedArgs["new_string"] ?? normalizedArgs["new_str"] ?? normalizedArgs["replace"] {
                normalizedArgs["replacement"] = r
            }
        }
        if normalizedArgs["command"] == nil {
            if let cmd = normalizedArgs["cmd"] {
                normalizedArgs["command"] = cmd
            }
        }

        // Default helpers for terminal execution
        if tool.id == "use_terminal" {
            if normalizedArgs["explanation"] == nil {
                normalizedArgs["explanation"] = "Execute command"
            }
            if normalizedArgs["estimatedImpact"] == nil {
                normalizedArgs["estimatedImpact"] = "Command execution"
            }
            if normalizedArgs["modifiesRepo"] == nil {
                normalizedArgs["modifiesRepo"] = "false"
            }
        }

        // Automatic path relativization
        let projectRoot = ProjectSessionStore.shared.activeProject?.directoryURL.path ?? ""
        for pathKey in ["path", "filePath", "sourcePath", "destinationPath", "source", "destination", "oldPath", "newName", "workingDirectory", "project"] {
            if var rawPath = normalizedArgs[pathKey] as? String {
                if !projectRoot.isEmpty && rawPath.hasPrefix(projectRoot) {
                    rawPath = String(rawPath.dropFirst(projectRoot.count))
                }
                while rawPath.hasPrefix("/") {
                    rawPath = String(rawPath.dropFirst())
                }
                normalizedArgs[pathKey] = rawPath
            }
        }

        var errors: [String] = []
        let schema = tool.parametersSchema

        if let required = schema.required {
            for key in required {
                if normalizedArgs[key] == nil {
                    errors.append("Missing required argument '\(key)' for tool '\(tool.id)'")
                }
            }
        }

        if let properties = schema.properties {
            for (key, propSchema) in properties {
                guard let value = normalizedArgs[key] else { continue }

                if !isValue(value, validForType: propSchema.type) {
                    errors.append("Argument '\(key)' has invalid type. Expected \(propSchema.type).")
                }
            }
        }

        // ".." is rejected for path keys, with two containment-checked
        // exceptions: dir_cd (its ".." means "parent", clamped at the root by
        // AssistFileSystem) and use_terminal's workingDirectory (resolved
        // through AssistFileSystem by UseTermFunction). Both are still
        // containment-checked downstream; the rejection here is defense in
        // depth for keys with no downstream containment check.
        if tool.id != "dir_cd" {
            for pathKey in ["path", "filePath", "sourcePath", "destinationPath", "source", "destination", "oldPath", "newName", "project"] {
                if let path = normalizedArgs[pathKey] as? String {
                    if path.contains("..") {
                        errors.append("Argument '\(pathKey)' contains unsafe directory traversal: \(path)")
                    }
                }
            }
        }

        if errors.isEmpty {
            return ToolValidationResult(isValid: true, issue: nil, correctedInput: normalizedArgs)
        } else {
            return ToolValidationResult(isValid: false, issue: errors.joined(separator: "; "))
        }
    }

    public func cachedSchema(for toolId: String) -> String? {
        return schemaCache[toolId]
    }

    public func setCachedSchema(_ schema: String, for toolId: String) {
        schemaCache[toolId] = schema
    }

    public func invalidateSchemaCache() {
        schemaCache.removeAll()
    }

    private func rebuildCapabilityIndex() {
        capabilityIndex.removeAll()
        for (id, tool) in tools {
            capabilityIndex[tool.capability, default: []].append(id)
        }
    }

    private func isValue(_ value: Any, validForType type: String) -> Bool {
        switch type {
        case "string":
            return value is String
        case "integer":
            return value is Int || value is Double
        case "number":
            return value is Double || value is Int || value is Float
        case "boolean":
            return value is Bool
        case "array":
            return value is [Any]
        case "object":
            return value is [String: Any]
        default:
            return true
        }
    }
}
