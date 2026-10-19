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

    public init() {
        registerAllTools()
    }

    private func registerAllTools() {
        register(AssistReadFileTool())
        register(AssistWriteFileTool())
        register(AssistAppendFileTool())
        register(AssistDeleteFileTool())
        register(AssistMoveFileTool())
        register(AssistCopyFileTool())
        register(AssistRenameFileTool())
        register(AssistCreateDirectoryTool())
        register(AssistCreateFileTool())
        register(AssistGenerateFileTool())
        register(AssistDeleteDirectoryTool())
        register(AssistReadDirectoryTool())
        register(AssistTreeViewTool())
        register(AssistChangeDirectoryTool())
        register(AssistPrintWorkingDirectoryTool())

        register(AssistSearchTool())
        register(AssistRegexSearchTool())
        register(AssistSymbolSearchTool())
        register(AssistDependencyGraphTool())
        register(AssistCodeSummaryTool())
        register(AssistLintTool())
        register(AssistComplexityAnalysisTool())

        register(AssistReplaceInFileTool())
        register(AssistMultiFileEditTool())
        register(AssistRefactorTool())
        register(AssistFormatCodeTool())
        register(AssistInsertCodeBlockTool())

        register(AssistSnapshotProjectTool())
        register(AssistRestoreSnapshotTool())
        register(AssistDiffTool())
        register(AssistChangeLogTool())
        register(AssistUndoTool())
        register(AssistValidateChangesTool())

        register(AssistTaskRunnerTool())
        register(AssistBuildProjectTool())
        register(AssistGenerateXcodeprojTool())
        register(AssistTestRunnerTool())
        register(AssistLogCaptureTool())
        register(AssistEnvironmentInfoTool())
        register(UseTermFunction())
        register(UseMCP())
        register(AssistComposioTool())

        register(AssistCreateNewAppTool())
        register(AssistPlanTaskTool())
        register(AssistBreakdownTaskTool())
        register(AssistAutoFixErrorsTool())
        register(AssistGenerateTestsTool())
        register(AssistExplainCodeTool())

        register(AssistStoreMemoryTool())
        register(AssistRetrieveMemoryTool())
        register(AssistClearMemoryTool())
        register(AssistContextSnapshotTool())

        register(AssistSourceGraphBuilder())
        register(AssistSemanticQueryEngine())
        register(AssistCodeMutationEngine())
        register(AssistPatchApplicationEngine())
        register(AssistProjectMutationController())
        register(AssistCompilerDiagnosticsEngine())
        register(AssistAutomatedRepairEngine())
        register(AssistVersionControlOperator())
        register(AssistContextPersistenceStore())
        register(AssistRuntimeDiagnosticsEngine())
        register(AssistExternalResourceGateway())
        register(AssistDependencyResolutionEngine())
        register(AssistAutonomousReviewEngine())
        register(CodeReviewTool())
        register(UseWorkersTool())
        register(ExecutionPlanTool())
        register(PlanAskUserTool())
        register(SearchSkillsTool())
        register(AssistOpenInFinderTool())
        register(AssistRevealInFinderTool())
        register(ReportToUserTool())

        // 15 New Specialized Engineering Tools
        register(AssistAssetCatalogTool())
        register(AssistSwiftPackageTool())
        register(AssistPlistTool())
        register(AssistCodeMetricsTool())
        register(AssistLocalizationTool())
        register(AssistMemoryLeakDetectorTool())
        register(AssistDeadCodeEliminatorTool())
        register(AssistInterfaceSimulatorTool())
        register(AssistDocStringGeneratorTool())
        register(AssistEntitlementsTool())
        register(AssistCodeSnippetTool())
        register(AssistSecurityAuditTool())
        register(AssistMigrationTool())
        register(AssistGitStashTool())
        register(AssistXcodeSchemeTool())

        // 45 New Deep Engineering, Diagnostics, Memory, & Tooling
        register(AssistSaveToMemoryTool())
        register(AssistViewMemoryTool())
        register(AssistManageMemoryTool())
        register(AssistConversationContextTool())
        register(AssistSwiftASTInspectorTool())
        register(AssistXcodeBuildSettingsTool())
        register(AssistSymbolReferenceGraphTool())
        register(AssistXCResultParserTool())
        register(AssistXcodeDeviceDestinationTool())
        register(AssistSimulatorControllerTool())
        register(AssistGitBlameTool())
        register(AssistGitBranchManagerTool())
        register(AssistGitLogViewerTool())
        register(AssistGitConflictResolverTool())
        register(AssistSwiftFormatLintTool())
        register(AssistTodoFixmeScannerTool())
        register(AssistUnusedImportsDetectorTool())
        register(AssistBundleResourceAuditorTool())
        register(AssistCoreDataModelInspectorTool())
        register(AssistSwiftDataSchemaAuditorTool())
        register(AssistPrivacyManifestAuditorTool())
        register(AssistIconGeneratorTool())
        register(AssistColorSetBuilderTool())
        register(AssistStringCatalogMigratorTool())
        register(AssistTestCoverageReporterTool())
        register(AssistSPMDependencyTreeTool())
        register(AssistPodfileInspectorTool())
        register(AssistCarthageCartfileInspectorTool())
        register(AssistMachOBinaryAnalyzerTool())
        register(AssistFrameworkLinkerAuditorTool())
        register(AssistSigningCertificateInspectorTool())
        register(AssistProvisioningProfileReaderTool())
        register(AssistNetworkSecurityAuditorTool())
        register(AssistAccessibilityAuditScannerTool())
        register(AssistSwiftConcurrencyAnalyzerTool())
        register(AssistRegexReplaceInFilesTool())
        register(AssistFileChecksumVerifierTool())
        register(AssistBinaryPlistConverterTool())
        register(AssistJSONValidatorTool())
        register(AssistYAMLParserTool())
        register(AssistEnvironmentVariableManagerTool())
        register(AssistClipboardManagerTool())
        register(AssistProcessMonitorTool())
        register(AssistDiskSpaceAnalyzerTool())
        register(AssistSystemNotificationTool())

        // Native Reverse subsystem (REA, static inspection only).
        register(ReverseToolAdapter())

        // 60 new tools (feature/assist-60-new-tools): Xcode project & build
        register(AssistProjectSchemeListTool())
        register(AssistProjectTargetListTool())
        register(AssistProjectBuildSettingsTool())
        register(AssistProjectTargetAddTool())
        register(AssistProjectEntitlementsTool())
        register(AssistProjectInfoPlistTool())
        register(AssistProjectCapabilitiesTool())
        register(AssistProjectSigningTool())
        register(AssistProjectCleanTool())
        register(AssistProjectArchiveTool())
        // SwiftPM + assets/resources
        register(AssistPackageManifestReadTool())
        register(AssistPackageDependencyAddTool())
        register(AssistPackageDependencyUpdateTool())
        register(AssistPackageManifestValidateTool())
        register(AssistPackageDependencyAuditTool())
        register(AssistAssetCatalogListTool())
        register(AssistAssetImageAddTool())
        register(AssistStringsLocalizationTool())
        register(AssistLocalizationAuditTool())
        register(AssistLocalizeAppTool())
        register(AssistPlistEditTool())
        // Code quality & analysis
        register(AssistDeadCodeScanTool())
        register(AssistDuplicateCodeScanTool())
        register(AssistTodoScanTool())
        register(AssistLicenseHeaderCheckTool())
        register(AssistApiSurfaceExtractTool())
        register(AssistSymbolRenameProjectTool())
        register(AssistSymbolMoveFileTool())
        register(AssistImportCleanupTool())
        register(AssistAccessLevelAuditTool())
        register(AssistConcurrencyAuditTool())
        // Testing & QA
        register(AssistTestCoverageReportTool())
        register(AssistTestFlakyDetectTool())
        register(AssistTestSnapshotManageTool())
        register(AssistUITestScaffoldTool())
        register(AssistTestDataFactoryTool())
        register(AssistTestTargetAddTool())
        register(AssistTestRunSingleTool())
        register(AssistTestLogParseTool())
        register(AssistPerformanceBenchmarkTool())
        register(AssistBinarySizeReportTool())
        // Git advanced + structured files
        register(AssistGitBisectTool())
        register(AssistGitCherryPickTool())
        register(AssistGitBranchCompareTool())
        register(AssistGitPRSummaryTool())
        register(AssistFileMetadataTool())
        register(AssistFileHashVerifyTool())
        register(AssistJsonValidateTool())
        register(AssistYamlValidateTool())
        // Environment, devices, docs, security
        register(AssistSimulatorListTool())
        register(AssistSimulatorBootTool())
        register(AssistDeviceListTool())
        register(AssistProvisioningCheckTool())
        register(AssistDoccBuildTool())
        register(AssistDocsGenerateTool())
        register(AssistSecretsScanTool())
        register(AssistPermissionsAuditTool())
        register(AssistAccessibilityAuditTool())
        register(AssistSessionExportTool())

        // Artboards & Visual UI Builder Subsystem tools
        register(AssistArtboardListTool())
        register(AssistArtboardGetTool())
        register(AssistArtboardCreateTool())
        register(AssistArtboardUpdateTool())
        register(AssistArtboardDeleteTool())
        register(AssistArtboardCompileTool())
        register(AssistArtboardRunAppTool())
        register(AssistFixArtboardsTool())

        // Archive & Compression tools
        register(AssistZipFileTool())
        register(AssistUnzipFileTool())
        register(AssistTarArchiveCreateTool())
        register(AssistTarArchiveExtractTool())
        register(AssistGzipCompressTool())
        register(AssistGzipDecompressTool())

        // Image & Decoder tools
        register(AssistImageDecodeBase64Tool())
        register(AssistImageEncodeBase64Tool())
        register(AssistImageGetDimensionsTool())
        register(AssistImageConvertFormatTool())
        register(AssistImageGenerateThumbnailTool())
        register(AssistImageExtractMetadataTool())
        register(AssistSvgToPngTool())

        // Data & Structured file tools
        register(AssistFormatJsonFileTool())
        register(AssistCsvToJsonTool())
        register(AssistJsonToCsvTool())
        register(AssistPlistToJsonTool())
        register(AssistJsonToPlistTool())
        register(AssistFileCompareDiffTool())
        register(AssistBatchRenameFilesTool())
        register(AssistCountFileLinesTool())
        register(AssistExtractCodeSymbolsTool())
        register(AssistGenerateFileChecksumTool())

        // Artifacts-intro expansion: 60 single-file tools (no git tooling).
        // Repository intelligence
        register(AssistRepoOverviewTool())
        register(AssistProjectStructureMapTool())
        register(AssistRecentChangesTool())
        register(AssistReadmeLocateTool())
        register(AssistDependencyLicensesTool())
        register(AssistStaleFilesReportTool())
        register(AssistEntryPointsDiscoverTool())
        register(AssistBuildSystemDetectTool())
        // Code navigation
        register(AssistCallHierarchyTool())
        register(AssistTypeHierarchyTool())
        register(AssistProtocolConformanceListTool())
        register(AssistImportGraphTool())
        register(AssistCommentDensityReportTool())
        register(AssistFunctionSizeReportTool())
        register(AssistStringLiteralAuditTool())
        register(AssistForceUnwrapScanTool())
        // File operations
        register(AssistDirSizeReportTool())
        register(AssistFindDuplicateFilesTool())
        register(AssistFileTypeBreakdownTool())
        register(AssistEmptyDirsFindTool())
        register(AssistFileHeadPreviewTool())
        register(AssistSymlinkAuditTool())
        register(AssistExecutableFilesScanTool())
        // Diagnostics
        register(AssistSystemTool())
        register(AssistBuildLogAnalyzeTool())
        register(AssistSchemeTestPlanListTool())
        register(AssistCodeSigningDiagnoseTool())
        register(AssistCrashLogParseTool())
        register(AssistEntitlementsDiffTool())
        register(AssistStringsFileValidateTool())
        register(AssistDeprecationUsageScanTool())
        register(AssistInfoPlistAuditTool())
        register(AssistApiEndpointAuditTool())
        register(AssistColorUsageAuditTool())
        register(AssistImageAssetSizeReportTool())
        register(AssistPbxprojLintTool())
        register(AssistXctestDiscoveryTool())
        // Build environment
        register(AssistXcodeToolchainInfoTool())
        register(AssistDerivedDataLocateTool())
        register(AssistBuildSettingsDiffTool())
        register(AssistTargetDependenciesListTool())
        register(AssistWorkspaceSettingsReadTool())
        register(AssistBuildPhaseScriptsListTool())
        register(AssistBuildConfigurationListTool())
        register(AssistTargetSourceListTool())
        // Documentation
        register(AssistReadmeGenerateTool())
        register(AssistDocsIndexBuildTool())
        register(AssistCodeCommentExtractTool())
        register(AssistApiDocsCoverageTool())
        register(AssistMarkdownLinkCheckTool())
        register(AssistMarkdownTocGenerateTool())
        // Native artifacts
        register(AssistCreateArtifactTool())
        register(AssistListArtifactsTool())
        register(AssistReadArtifactTool())
        register(AssistDeleteArtifactTool())
        // Workflow
        register(AssistSessionProgressReportTool())
        register(AssistPreflightChecksTool())
        register(AssistChangeImpactEstimateTool())
        register(AssistFileBackupTool())
        register(AssistConflictMarkerScanTool())
        register(AssistToolCapabilityLookupTool())

        // Native Screen Capture, Recording & App Interaction
        register(AssistTakeScreenshotTool())
        register(AssistTakeScreenrecordTool())
        register(AssistUseAppTool())
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
