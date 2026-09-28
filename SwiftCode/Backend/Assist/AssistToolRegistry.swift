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
    private var tools: [String: AssistTool] = [:]
    private var health: [String: ToolHealth] = [:]
    private var capabilityIndex: [ToolCapability: [String]] = [:]
    private var schemaCache: [String: String] = [:]
    private var registryVersion: Int = 0

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
        register(AssistTestRunnerTool())
        register(AssistLogCaptureTool())
        register(AssistEnvironmentInfoTool())
        register(UseTermFunction())
        register(UseMCP())
        register(AssistComposioTool())

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
    }

    public var version: Int { registryVersion }

    public func register(_ tool: AssistTool) {
        tools[tool.id] = tool
        health[tool.id] = ToolHealth(toolId: tool.id, status: .available)
        rebuildCapabilityIndex()
        schemaCache.removeAll()
        registryVersion += 1
    }

    public func unregister(_ toolId: String) {
        tools.removeValue(forKey: toolId)
        health.removeValue(forKey: toolId)
        rebuildCapabilityIndex()
        schemaCache.removeAll()
        registryVersion += 1
    }

    public func getTool(_ id: String) -> AssistTool? {
        return tools[id]
    }

    public var allTools: [AssistTool] {
        return Array(tools.values).sorted(by: { $0.id < $1.id })
    }

    public func getToolSchemas() -> [[String: Any]] {
        return allTools.map { tool in
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
        guard let tool = tools[toolId] else {
            return ToolValidationResult(isValid: false, issue: "Tool '\(toolId)' is not registered")
        }

        if let toolHealth = health[toolId], toolHealth.status == .disabled {
            return ToolValidationResult(isValid: false, issue: "Tool '\(toolId)' is disabled")
        }

        if let toolHealth = health[toolId], toolHealth.status == .temporarilyUnavailable {
            return ToolValidationResult(isValid: false, issue: "Tool '\(toolId)' is temporarily unavailable")
        }

        var errors: [String] = []
        let schema = tool.parametersSchema

        if let required = schema.required {
            for key in required {
                if arguments[key] == nil {
                    errors.append("Missing required argument '\(key)' for tool '\(toolId)'")
                }
            }
        }

        if let properties = schema.properties {
            for (key, propSchema) in properties {
                guard let value = arguments[key] else { continue }

                if !isValue(value, validForType: propSchema.type) {
                    errors.append("Argument '\(key)' has invalid type. Expected \(propSchema.type).")
                }
            }
        }

        for pathKey in ["path", "filePath", "sourcePath", "destinationPath"] {
            if let path = arguments[pathKey] as? String {
                if path.contains("..") || path.hasPrefix("/") {
                    errors.append("Argument '\(pathKey)' contains unsafe path: \(path)")
                }
            }
        }

        if errors.isEmpty {
            return ToolValidationResult(isValid: true, issue: nil, correctedInput: arguments)
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
