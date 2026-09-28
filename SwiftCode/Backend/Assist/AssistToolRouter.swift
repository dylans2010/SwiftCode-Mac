import Foundation

// MARK: - Assist v3 Tool Capabilities & Risk Levels

public enum ToolCapability: String, Codable, Sendable, CaseIterable {
    case repositoryDiscovery = "Repository Discovery"
    case fileReading = "File Reading"
    case fileModification = "File Modification"
    case compilation = "Compilation & Build"
    case testing = "Testing & QA"
    case diagnostics = "Diagnostics & Profiling"
    case gitOperations = "Version Control (Git)"
    case systemExecution = "System & Shell Execution"
    case planning = "Task Planning"
    case memory = "Agent Memory"
    case general = "General"
}

public enum ToolRiskLevel: String, Codable, Sendable, Comparable {
    case safeRead = "Safe Read"
    case safeMutation = "Safe Mutation"
    case execution = "Execution"
    case potentiallyDestructive = "Potentially Destructive"
    case externalSideEffect = "External Side Effect"

    private var rank: Int {
        switch self {
        case .safeRead: return 0
        case .safeMutation: return 1
        case .execution: return 2
        case .potentiallyDestructive: return 3
        case .externalSideEffect: return 4
        }
    }

    public static func < (lhs: ToolRiskLevel, rhs: ToolRiskLevel) -> Bool {
        return lhs.rank < rhs.rank
    }
}

public struct ToolMetadata: Codable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let capability: ToolCapability
    public let riskLevel: ToolRiskLevel
    public let isReadOnly: Bool
    public let isMutating: Bool
    public let requiresVerificationAfterward: Bool

    public init(
        id: String,
        name: String,
        description: String,
        capability: ToolCapability,
        riskLevel: ToolRiskLevel,
        isReadOnly: Bool,
        isMutating: Bool,
        requiresVerificationAfterward: Bool
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.capability = capability
        self.riskLevel = riskLevel
        self.isReadOnly = isReadOnly
        self.isMutating = isMutating
        self.requiresVerificationAfterward = requiresVerificationAfterward
    }
}

// MARK: - Assist v3 Tool Router

@MainActor
public final class AssistToolRouter: Sendable {
    public static let shared = AssistToolRouter()

    private init() {}

    public func metadata(for toolId: String) -> ToolMetadata {
        switch toolId {
        case "file_read", "read_file":
            return ToolMetadata(id: toolId, name: "Read File", description: "Read file content with targeted lines.", capability: .fileReading, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "directory_read", "list_directory", "read_dir":
            return ToolMetadata(id: toolId, name: "Read Directory", description: "Lists directory contents.", capability: .repositoryDiscovery, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "project_search", "search_files", "find_text":
            return ToolMetadata(id: toolId, name: "Search Files", description: "Searches text in files.", capability: .repositoryDiscovery, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "symbol_search", "find_symbol":
            return ToolMetadata(id: toolId, name: "Search Symbol", description: "Finds symbol declarations.", capability: .repositoryDiscovery, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "tree_view":
            return ToolMetadata(id: toolId, name: "Tree View", description: "ASCII folder tree hierarchy.", capability: .repositoryDiscovery, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)

        case "file_write", "write_file":
            return ToolMetadata(id: toolId, name: "Write File", description: "Writes full file content atomically.", capability: .fileModification, riskLevel: .safeMutation, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)
        case "code_replace", "replace_in_file", "edit_file":
            return ToolMetadata(id: toolId, name: "Replace in File", description: "Replaces target string in file.", capability: .fileModification, riskLevel: .safeMutation, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)
        case "file_create", "create_file":
            return ToolMetadata(id: toolId, name: "Create File", description: "Scaffolds new file.", capability: .fileModification, riskLevel: .safeMutation, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)
        case "insert_code_block":
            return ToolMetadata(id: toolId, name: "Insert Code Block", description: "Inserts block relative to anchor.", capability: .fileModification, riskLevel: .safeMutation, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)
        case "file_delete", "delete_file":
            return ToolMetadata(id: toolId, name: "Delete File", description: "Deletes file with snapshot.", capability: .fileModification, riskLevel: .potentiallyDestructive, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)
        case "file_rename", "file_move":
            return ToolMetadata(id: toolId, name: "Move/Rename File", description: "Moves or renames files.", capability: .fileModification, riskLevel: .safeMutation, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)

        case "project_build", "build_project", "run_build":
            return ToolMetadata(id: toolId, name: "Build Project", description: "Builds macOS project via xcodebuild.", capability: .compilation, riskLevel: .execution, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "project_test", "run_tests":
            return ToolMetadata(id: toolId, name: "Run Tests", description: "Executes unit/integration tests.", capability: .testing, riskLevel: .execution, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "compiler_diagnostics_engine", "diagnostics":
            return ToolMetadata(id: toolId, name: "Compiler Diagnostics", description: "Captures compiler warnings and errors.", capability: .diagnostics, riskLevel: .execution, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "project_diff", "git_diff":
            return ToolMetadata(id: toolId, name: "Project Diff", description: "Generates Git/snapshot diff of active edits.", capability: .gitOperations, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "code_review":
            return ToolMetadata(id: toolId, name: "Code Review", description: "Autonomous code review evaluation gate.", capability: .diagnostics, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)

        case "use_workers":
            return ToolMetadata(id: toolId, name: "Use Workers", description: "Creates, schedules, and executes isolated concurrent/sequential Workers for complex tasks.", capability: .planning, riskLevel: .execution, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)

        case "use_terminal", "execute_terminal_command", "terminal_command":
            return ToolMetadata(id: toolId, name: "Execute Terminal Command", description: "Executes shell commands in workspace.", capability: .systemExecution, riskLevel: .execution, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)

        default:
            return ToolMetadata(id: toolId, name: toolId, description: "Assist tool.", capability: .general, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        }
    }

    public func filterTools(for status: AgentSessionStatus, in registry: AssistToolRegistry) -> [AssistTool] {
        let all = registry.allTools

        switch status {
        case .analyzingRepository, .collectingContext, .gatheringContext, .understandingRequest:
            return all.filter { tool in
                let meta = metadata(for: tool.id)
                return meta.capability == .repositoryDiscovery ||
                       meta.capability == .fileReading ||
                       meta.capability == .planning ||
                       tool.id == "project_diff"
            }

        case .planning, .planningReview:
            return all.filter { tool in
                let meta = metadata(for: tool.id)
                return meta.capability == .planning ||
                       meta.capability == .repositoryDiscovery ||
                       meta.capability == .fileReading ||
                       tool.id == "code_summary" ||
                       tool.id == "use_workers"
            }

        case .executingTools, .updatingRepository, .executingStrategy:
            return all.filter { tool in
                let meta = metadata(for: tool.id)
                return meta.capability == .fileModification ||
                       meta.capability == .fileReading ||
                       meta.capability == .systemExecution ||
                       tool.id == "code_replace" ||
                       tool.id == "file_write" ||
                       tool.id == "project_diff" ||
                       tool.id == "use_workers"
            }

        case .validating, .reviewing:
            return all.filter { tool in
                let meta = metadata(for: tool.id)
                return meta.capability == .compilation ||
                       meta.capability == .testing ||
                       meta.capability == .diagnostics ||
                       meta.capability == .gitOperations ||
                       tool.id == "code_review" ||
                       tool.id == "compiler_diagnostics_engine"
            }

        case .recovering, .reviewFailed:
            return all.filter { tool in
                let meta = metadata(for: tool.id)
                return meta.capability == .diagnostics ||
                       meta.capability == .fileReading ||
                       meta.capability == .fileModification ||
                       meta.capability == .compilation
            }

        default:
            return all
        }
    }

    public func selectTools(forCapability capability: ToolCapability, in registry: AssistToolRegistry) -> [AssistTool] {
        return registry.toolsForCapability(capability)
    }

    public func selectTools(forCapabilities capabilities: [ToolCapability], in registry: AssistToolRegistry) -> [AssistTool] {
        var seen = Set<String>()
        var result: [AssistTool] = []
        for capability in capabilities {
            for tool in registry.toolsForCapability(capability) {
                if !seen.contains(tool.id) {
                    seen.insert(tool.id)
                    result.append(tool)
                }
            }
        }
        return result
    }

    public func serializeToolSchemas(_ tools: [AssistTool]) -> String {
        return tools.map { tool in
            let meta = metadata(for: tool.id)
            let schemaData = (try? JSONEncoder().encode(tool.parametersSchema)) ?? Data()
            let schemaStr = String(data: schemaData, encoding: .utf8) ?? "{}"
            return """
            - id: "\(tool.id)"
              name: "\(tool.name)"
              category: "\(meta.capability.rawValue)"
              risk: "\(meta.riskLevel.rawValue)"
              description: "\(tool.description)"
              parameters: \(schemaStr)
            """
        }.joined(separator: "\n\n")
    }

    public func serializeCompactSchemas(_ tools: [AssistTool]) -> String {
        return tools.map { tool in
            let meta = metadata(for: tool.id)
            return """
            - id: "\(tool.id)"
              name: "\(tool.name)"
              category: "\(meta.capability.rawValue)"
              risk: "\(meta.riskLevel.rawValue)"
              description: "\(tool.description)"
            """
        }.joined(separator: "\n\n")
    }

    public func compactCapabilitySummary(for registry: AssistToolRegistry) -> String {
        let capMap = registry.compactCapabilityRepresentation
        var lines: [String] = []
        for capability in ToolCapability.allCases {
            if let ids = capMap[capability.rawValue], !ids.isEmpty {
                lines.append("\(capability.rawValue): \(ids.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }
}
