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

    public nonisolated func metadata(for toolId: String) -> ToolMetadata {
        Self.metadata(for: toolId)
    }

    public nonisolated static func metadata(for toolId: String) -> ToolMetadata {
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
        case "search_skills":
            return ToolMetadata(id: toolId, name: "Search Skills", description: "Search authoritative local agent skills library.", capability: .repositoryDiscovery, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)

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

        case "open_in_finder", "open_finder":
            return ToolMetadata(id: toolId, name: "Open in Finder", description: "Opens file or directory in macOS Finder.", capability: .systemExecution, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "reveal_in_finder", "reveal_finder":
            return ToolMetadata(id: toolId, name: "Reveal in Finder", description: "Reveals and highlights file or directory in Finder.", capability: .systemExecution, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "version_control_operator", "git":
            return ToolMetadata(id: toolId, name: "Version Control Operator", description: "Performs git operations including status, diff, commit, and branch.", capability: .gitOperations, riskLevel: .safeMutation, isReadOnly: false, isMutating: true, requiresVerificationAfterward: false)

        case "use_workers":
            return ToolMetadata(id: toolId, name: "Use Workers", description: "Creates, schedules, and executes isolated concurrent/sequential Workers for complex tasks.", capability: .planning, riskLevel: .execution, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)

        case "use_terminal", "execute_terminal_command", "terminal_command":
            return ToolMetadata(id: toolId, name: "Execute Terminal Command", description: "Executes shell commands in workspace.", capability: .systemExecution, riskLevel: .execution, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)

        case "report_to_user", "reporttouser":
            return ToolMetadata(id: toolId, name: "Report to User", description: "Reports completed task summary and verified results to the user.", capability: .general, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)

        default:
            return ToolMetadata(id: toolId, name: toolId, description: "Assist tool.", capability: .general, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        }
    }

    /// Builds metadata from a registered tool's own declared properties.
    /// This is the single source of truth for capability and risk: tools declare
    /// their own `capability` and `riskLevel`, and routing/serialization derive
    /// from those declarations. The `metadata(for toolId:)` overload remains as a
    /// fallback for unregistered or legacy tool ids.
    public func metadata(for tool: AssistTool) -> ToolMetadata {
        ToolMetadata(
            id: tool.id,
            name: tool.name,
            description: tool.description,
            capability: tool.capability,
            riskLevel: tool.riskLevel,
            isReadOnly: tool.isReadOnly,
            isMutating: tool.isMutating,
            requiresVerificationAfterward: tool.isMutating
        )
    }

    public func filterTools(for status: AgentSessionStatus, in registry: AssistToolRegistry) -> [AssistTool] {
        return filterTools(for: nil, status: status, in: registry)
    }

    public func filterTools(for intent: UserIntent?, status: AgentSessionStatus, in registry: AssistToolRegistry) -> [AssistTool] {
        let all = registry.allTools

        switch status {
        case .analyzingRepository, .collectingContext, .gatheringContext, .understandingRequest:
            return all.filter { tool in
                return tool.capability == .repositoryDiscovery ||
                       tool.capability == .fileReading ||
                       tool.capability == .planning ||
                       tool.id == "project_diff"
            }

        case .planning, .planningReview:
            if let intent = intent {
                switch intent {
                case .git:
                    return rankTools(for: intent, in: all.filter { $0.capability == .gitOperations || $0.capability == .planning || $0.id == "version_control_operator" || $0.id == "project_diff" || $0.capability == .fileReading })
                case .build:
                    return rankTools(for: intent, in: all.filter { $0.capability == .compilation || $0.capability == .diagnostics || $0.capability == .planning || $0.capability == .fileReading })
                case .test:
                    return rankTools(for: intent, in: all.filter { $0.capability == .testing || $0.capability == .compilation || $0.capability == .planning })
                case .fileOperation(let action, _):
                    if action == .openInFinder || action == .revealInFinder {
                        return all.filter { $0.id == "open_in_finder" || $0.id == "reveal_in_finder" || $0.capability == .systemExecution || $0.capability == .planning }
                    }
                default:
                    break
                }
            }
            return all.filter { tool in
                return tool.capability == .planning ||
                       tool.capability == .repositoryDiscovery ||
                       tool.capability == .fileReading ||
                       tool.capability == .gitOperations ||
                       tool.capability == .compilation ||
                       tool.id == "version_control_operator" ||
                       tool.id == "project_build" ||
                       tool.id == "code_summary" ||
                       tool.id == "use_workers"
            }

        case .executingTools, .updatingRepository, .executingStrategy:
            return all.filter { tool in
                return tool.capability == .fileModification ||
                       tool.capability == .fileReading ||
                       tool.capability == .gitOperations ||
                       tool.capability == .compilation ||
                       tool.capability == .testing ||
                       tool.capability == .systemExecution ||
                       tool.id == "code_replace" ||
                       tool.id == "file_write" ||
                       tool.id == "project_diff" ||
                       tool.id == "version_control_operator" ||
                       tool.id == "project_build" ||
                       tool.id == "use_workers"
            }

        case .validating, .reviewing:
            return all.filter { tool in
                return tool.capability == .compilation ||
                       tool.capability == .testing ||
                       tool.capability == .diagnostics ||
                       tool.id == "code_review" ||
                       tool.id == "compiler_diagnostics_engine" ||
                       tool.id == "project_build"
            }

        case .recovering, .reviewFailed:
            return all.filter { tool in
                return tool.capability == .diagnostics ||
                       tool.capability == .fileReading ||
                       tool.capability == .fileModification ||
                       tool.capability == .compilation ||
                       tool.capability == .gitOperations
            }

        default:
            return all
        }
    }

    public func rankTools(for intent: UserIntent, in tools: [AssistTool]) -> [AssistTool] {
        return tools.sorted { t1, t2 in
            let score1 = capabilityScore(for: t1, intent: intent)
            let score2 = capabilityScore(for: t2, intent: intent)
            if score1 != score2 { return score1 > score2 }
            if t1.id != "use_terminal" && t2.id == "use_terminal" { return true }
            if t1.id == "use_terminal" && t2.id != "use_terminal" { return false }
            return t1.name < t2.name
        }
    }

    private func capabilityScore(for tool: AssistTool, intent: UserIntent) -> Int {
        switch intent {
        case .git:
            if tool.id == "version_control_operator" { return 100 }
            if tool.id == "project_diff" { return 80 }
            if tool.capability == .gitOperations { return 70 }
            if tool.capability == .fileReading { return 20 }
            return 0
        case .build:
            if tool.id == "project_build" { return 100 }
            if tool.id == "compiler_diagnostics_engine" { return 80 }
            if tool.capability == .compilation { return 70 }
            return 0
        case .test:
            if tool.id == "project_test" { return 100 }
            if tool.capability == .testing { return 80 }
            if tool.capability == .compilation { return 50 }
            return 0
        case .codeSearch(let type, _):
            if type == .symbol && tool.id == "search_symbol" { return 100 }
            if type == .regex && tool.id == "search_regex" { return 100 }
            if type == .text && tool.id == "search_text" { return 100 }
            if tool.capability == .repositoryDiscovery { return 50 }
            return 0
        case .fileOperation(let action, _):
            if action == .openInFinder && tool.id == "open_in_finder" { return 100 }
            if action == .revealInFinder && tool.id == "reveal_in_finder" { return 100 }
            if action == .read && tool.id == "file_read" { return 100 }
            if action == .write && tool.id == "file_write" { return 100 }
            if action == .replace && tool.id == "code_replace" { return 100 }
            if tool.capability == .fileModification || tool.capability == .fileReading { return 50 }
            return 0
        case .workerDelegation:
            if tool.id == "use_workers" { return 100 }
            if tool.capability == .planning { return 50 }
            return 0
        default:
            return 10
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
            let meta = metadata(for: tool)
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
            let meta = metadata(for: tool)
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
