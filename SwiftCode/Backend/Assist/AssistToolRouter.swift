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

public enum ToolOutputFormat: String, Codable, Sendable {
    case text = "Text"
    case image = "Image"
    case video = "Video"
    case file = "File"
    case structuredData = "Structured Data"
}

public enum ToolPermissionRequirement: String, Codable, Sendable {
    case none = "None"
    case screenRecording = "Screen Recording"
    case accessibility = "Accessibility"
    case fileSystem = "File System"
    case terminalExecution = "Terminal Execution"
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

    // Unified capability extensions:
    public let outputFormat: ToolOutputFormat
    public let requiredPermission: ToolPermissionRequirement
    public let prerequisites: [String]
    public let supportedOperations: [String]
    public let knownLimitations: [String]
    public let canChainResult: Bool
    public let isDestructive: Bool
    public let resourceScope: String

    public init(
        id: String,
        name: String,
        description: String,
        capability: ToolCapability,
        riskLevel: ToolRiskLevel,
        isReadOnly: Bool,
        isMutating: Bool,
        requiresVerificationAfterward: Bool,
        outputFormat: ToolOutputFormat = .text,
        requiredPermission: ToolPermissionRequirement = .none,
        prerequisites: [String] = [],
        supportedOperations: [String] = [],
        knownLimitations: [String] = [],
        canChainResult: Bool = true,
        isDestructive: Bool = false,
        resourceScope: String = "Workspace Project"
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.capability = capability
        self.riskLevel = riskLevel
        self.isReadOnly = isReadOnly
        self.isMutating = isMutating
        self.requiresVerificationAfterward = requiresVerificationAfterward
        self.outputFormat = outputFormat
        self.requiredPermission = requiredPermission
        self.prerequisites = prerequisites
        self.supportedOperations = supportedOperations
        self.knownLimitations = knownLimitations
        self.canChainResult = canChainResult
        self.isDestructive = isDestructive
        self.resourceScope = resourceScope
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
            return ToolMetadata(id: toolId, name: "Read File", description: "Read file content; supports an optional lines {start,end} range.", capability: .fileReading, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "dir_read", "directory_read", "list_directory", "read_dir":
            return ToolMetadata(id: toolId, name: "Read Directory", description: "Lists directory contents.", capability: .fileReading, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "dir_cd":
            return ToolMetadata(id: toolId, name: "Change Directory", description: "Changes the session working directory.", capability: .fileReading, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "dir_pwd":
            return ToolMetadata(id: toolId, name: "Print Working Directory", description: "Reports the session working directory.", capability: .fileReading, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "dir_create", "create_directory", "make_directory", "directory_create":
            return ToolMetadata(id: toolId, name: "Create Directory", description: "Creates a directory.", capability: .fileModification, riskLevel: .safeMutation, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)
        case "dir_delete", "delete_directory", "remove_directory", "directory_delete":
            return ToolMetadata(id: toolId, name: "Delete Directory", description: "Recursively deletes a directory. Destructive.", capability: .fileModification, riskLevel: .potentiallyDestructive, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)
        case "file_copy", "copy_file":
            return ToolMetadata(id: toolId, name: "Copy File", description: "Copies a file; refuses when the destination exists.", capability: .fileModification, riskLevel: .safeMutation, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)
        case "file_append":
            return ToolMetadata(id: toolId, name: "Append File", description: "Appends content to an existing file.", capability: .fileModification, riskLevel: .safeMutation, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)
        case "code_insert", "insert_code_block", "insert_code":
            return ToolMetadata(id: toolId, name: "Insert Code Block", description: "Inserts block relative to anchor.", capability: .fileModification, riskLevel: .safeMutation, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)
        case "code_multi_edit":
            return ToolMetadata(id: toolId, name: "Multi-file Edit", description: "Applies edits across multiple files. Not atomic.", capability: .fileModification, riskLevel: .safeMutation, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)
        case "search_text", "project_search", "search_files", "find_text", "search", "find_file", "search_dir", "search_directory":
            return ToolMetadata(id: toolId, name: "Search Files", description: "Searches text in files.", capability: .repositoryDiscovery, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "search_regex":
            return ToolMetadata(id: toolId, name: "Search Regex", description: "Regex search across files.", capability: .repositoryDiscovery, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)
        case "search_symbol", "find_symbol":
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

        case "reverse_analyze", "reverse":
            return ToolMetadata(id: toolId, name: "Reverse Analyze", description: "Static reverse-engineering analysis of an authorized artifact via the native Reverse subsystem (REA).", capability: .diagnostics, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)

        case "use_workers":
            return ToolMetadata(id: toolId, name: "Use Workers", description: "Creates, schedules, and executes isolated concurrent/sequential Workers for complex tasks.", capability: .planning, riskLevel: .execution, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)

        case "use_terminal", "execute_terminal_command", "terminal_command":
            return ToolMetadata(id: toolId, name: "Execute Terminal Command", description: "Executes shell commands in workspace.", capability: .systemExecution, riskLevel: .execution, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)

        case "report_to_user", "reporttouser":
            return ToolMetadata(id: toolId, name: "Report to User", description: "Reports completed task summary and verified results to the user.", capability: .general, riskLevel: .safeRead, isReadOnly: true, isMutating: false, requiresVerificationAfterward: false)

        case "take_screenshot", "screenshot":
            return ToolMetadata(
                id: toolId,
                name: "Take Screenshot",
                description: "Captures full screen or region as PNG for visual analysis.",
                capability: .diagnostics,
                riskLevel: .safeRead,
                isReadOnly: true,
                isMutating: false,
                requiresVerificationAfterward: false,
                outputFormat: .image,
                requiredPermission: .screenRecording,
                prerequisites: ["Screen Recording permission granted"],
                supportedOperations: ["fullscreen", "region"],
                knownLimitations: ["Requires Screen Recording authorization in macOS System Settings."],
                canChainResult: true,
                isDestructive: false,
                resourceScope: "macOS Screen / Window"
            )
        case "take_screenrecord", "screenrecord":
            return ToolMetadata(
                id: toolId,
                name: "Take Screen Recording",
                description: "Records screen of a specifically identified application.",
                capability: .diagnostics,
                riskLevel: .safeRead,
                isReadOnly: true,
                isMutating: false,
                requiresVerificationAfterward: false,
                outputFormat: .video,
                requiredPermission: .screenRecording,
                prerequisites: ["Screen Recording permission granted", "Target application identified and running"],
                supportedOperations: ["window", "application_display"],
                knownLimitations: ["Audio capture is not supported; captures video stream of target application only.", "Maximum duration is 60 seconds."],
                canChainResult: true,
                isDestructive: false,
                resourceScope: "Target macOS Application Window"
            )
        case "use_app", "interact_app":
            return ToolMetadata(
                id: toolId,
                name: "Use App",
                description: "Interacts with macOS applications via Accessibility and UI automation.",
                capability: .systemExecution,
                riskLevel: .safeMutation,
                isReadOnly: false,
                isMutating: true,
                requiresVerificationAfterward: true,
                outputFormat: .structuredData,
                requiredPermission: .accessibility,
                prerequisites: ["Accessibility permission granted", "Target application running"],
                supportedOperations: ["launch", "activate", "list_applications", "inspect_application", "list_windows", "select_window", "close_application", "inspect_ui", "get_accessibility_tree", "get_focused_element", "take_screenshot", "inspect_window", "click", "double_click", "right_click", "move_pointer", "drag", "scroll", "type_text", "press_key", "press_shortcut", "select_all", "copy", "paste", "activate_element", "set_element_value", "select_menu", "wait_for_element", "wait_for_window", "verify"],
                knownLimitations: ["Requires Accessibility authorization in macOS System Settings.", "Target app must expose standard macOS Accessibility elements."],
                canChainResult: true,
                isDestructive: false,
                resourceScope: "Target macOS Application"
            )

        default:
            // Fail closed: unknown tools must never default to safe/read-only,
            // or the phase gate and permission checks would treat a destructive
            // or mutating tool as harmless. Callers with a registry should use
            // metadata(for: tool), which derives from the tool's own declaration.
            return ToolMetadata(id: toolId, name: toolId, description: "Unknown tool — fail closed.", capability: .general, riskLevel: .potentiallyDestructive, isReadOnly: false, isMutating: true, requiresVerificationAfterward: true)
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
            requiresVerificationAfterward: tool.isMutating,
            outputFormat: tool.outputFormat,
            requiredPermission: tool.requiredPermission,
            prerequisites: tool.prerequisites,
            supportedOperations: tool.supportedOperations,
            knownLimitations: tool.knownLimitations,
            canChainResult: tool.canChainResult,
            isDestructive: tool.isDestructive,
            resourceScope: tool.resourceScope
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
                case .screenshot:
                    return rankTools(for: intent, in: all.filter { $0.id == "take_screenshot" || $0.id == "use_app" || $0.capability == .diagnostics })
                case .screenRecording:
                    return rankTools(for: intent, in: all.filter { $0.id == "take_screenrecord" || $0.id == "use_app" || $0.capability == .diagnostics })
                case .appInteraction:
                    return rankTools(for: intent, in: all.filter { $0.id == "use_app" || $0.id == "open_in_finder" || $0.id == "reveal_in_finder" || $0.capability == .systemExecution })
                case .multiStep:
                    return rankTools(for: intent, in: all.filter { $0.id == "use_app" || $0.id == "take_screenshot" || $0.id == "take_screenrecord" || $0.capability == .systemExecution || $0.capability == .diagnostics || $0.capability == .planning })
                case .informational:
                    return []
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
            if let intent = intent {
                switch intent {
                case .screenshot:
                    return rankTools(for: intent, in: all.filter { $0.id == "take_screenshot" || $0.id == "use_app" || $0.capability == .diagnostics })
                case .screenRecording:
                    return rankTools(for: intent, in: all.filter { $0.id == "take_screenrecord" || $0.id == "use_app" || $0.capability == .diagnostics })
                case .appInteraction:
                    return rankTools(for: intent, in: all.filter { $0.id == "use_app" || $0.id == "open_in_finder" || $0.id == "reveal_in_finder" || $0.capability == .systemExecution })
                case .multiStep:
                    return rankTools(for: intent, in: all.filter { $0.id == "use_app" || $0.id == "take_screenshot" || $0.id == "take_screenrecord" || $0.capability == .systemExecution || $0.capability == .diagnostics || $0.capability == .planning })
                case .informational:
                    return []
                default:
                    break
                }
            }
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
        case .screenshot:
            if tool.id == "take_screenshot" { return 100 }
            if tool.id == "use_app" { return 70 }
            if tool.capability == .diagnostics { return 50 }
            return 0
        case .screenRecording:
            if tool.id == "take_screenrecord" { return 100 }
            if tool.id == "use_app" { return 70 }
            if tool.capability == .diagnostics { return 50 }
            return 0
        case .appInteraction:
            if tool.id == "use_app" { return 100 }
            if tool.id == "open_in_finder" || tool.id == "reveal_in_finder" { return 60 }
            if tool.capability == .systemExecution { return 50 }
            return 0
        case .multiStep(let subIntents):
            var maxScore = 0
            for sub in subIntents {
                maxScore = max(maxScore, capabilityScore(for: tool, intent: sub))
            }
            return maxScore
        case .informational:
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

// MARK: - Unified Tool Capability Catalog

@MainActor
public final class ToolCapabilityCatalog: Sendable {
    public static let shared = ToolCapabilityCatalog()

    public init() {}

    public func catalog(for registry: AssistToolRegistry) -> [ToolMetadata] {
        return registry.allTools.map { AssistToolRouter.shared.metadata(for: $0) }
    }

    public func validateRegistration(in registry: AssistToolRegistry) -> [String] {
        var issues: [String] = []
        var seenIds = Set<String>()
        for tool in registry.allTools {
            if seenIds.contains(tool.id) {
                issues.append("Duplicate tool identifier registered: \(tool.id)")
            }
            seenIds.insert(tool.id)
            if tool.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("Tool \(tool.id) has empty name")
            }
            if tool.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("Tool \(tool.id) has empty description")
            }
        }
        return issues
    }

    public func generateCompactCatalogPrompt(for registry: AssistToolRegistry) -> String {
        let tools = registry.allTools
        var lines: [String] = ["Available Tools and Capabilities:"]
        for tool in tools {
            let meta = AssistToolRouter.shared.metadata(for: tool)
            var line = "- `\(tool.id)`: \(meta.name) — \(meta.description)"
            if meta.requiredPermission != .none {
                line += " [Permission: \(meta.requiredPermission.rawValue)]"
            }
            if !meta.supportedOperations.isEmpty {
                line += " [Operations: \(meta.supportedOperations.prefix(5).joined(separator: ", "))]"
            }
            if !meta.knownLimitations.isEmpty {
                line += " [Limitation: \(meta.knownLimitations[0])]"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
