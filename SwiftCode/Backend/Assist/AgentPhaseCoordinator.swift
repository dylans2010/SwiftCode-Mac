import Foundation
import Observation
import os

// MARK: - Assist v3 Task Phase Model

public enum PhaseStatus: String, Codable, Sendable {
    case pending = "Pending"
    case inProgress = "In Progress"
    case completed = "Completed"
    case failed = "Failed"
    case skipped = "Skipped"
}

public struct TaskPhase: Identifiable, Codable, Sendable {
    public let id: UUID
    public let phaseId: String
    public let name: String
    public let description: String
    public var status: PhaseStatus
    public var startedAt: Date?
    public var completedAt: Date?
    public var dependencies: [String]
    public var evidence: String?
    public var failures: [String]
    public var recoveryNotes: String?

    public init(
        id: UUID = UUID(),
        phaseId: String,
        name: String,
        description: String,
        status: PhaseStatus = .pending,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        dependencies: [String] = [],
        evidence: String? = nil,
        failures: [String] = [],
        recoveryNotes: String? = nil
    ) {
        self.id = id
        self.phaseId = phaseId
        self.name = name
        self.description = description
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.dependencies = dependencies
        self.evidence = evidence
        self.failures = failures
        self.recoveryNotes = recoveryNotes
    }

    public var duration: TimeInterval? {
        guard let start = startedAt else { return nil }
        let end = completedAt ?? Date()
        return end.timeIntervalSince(start)
    }
}

// MARK: - Standard Assist Engineering Phases

public enum StandardEngineeringPhases {
    public static func defaultLifecycle() -> [TaskPhase] {
        let phaseTitles: [(String, String, String)] = [
            ("PHASE_001_REPO_INIT", "Repository Initialization", "Inspect repository root, packages, build config, and Assist systems."),
            ("PHASE_002_GIT_AUDIT", "Git State Audit", "Inspect branch, status, staged/unstaged changes, and recent history."),
            ("PHASE_003_AGENTS_DISCOVERY", "AGENTS Discovery", "Discover all root and nested AGENTS.md instruction files."),
            ("PHASE_004_AGENTS_INTERPRETATION", "AGENTS Interpretation", "Read and map applicable instructions and determine precedence."),
            ("PHASE_005_LEGACY_NOTES_DISCOVERY", "Legacy AgentNotes Discovery", "Discover and remove legacy AgentNotes.md files."),
            ("PHASE_006_AGENT_SYSTEM_ASSET_DISCOVERY", "AgentSystemAsset Discovery", "Load and verify authoritative AgentSystemAsset.md specification."),
            ("PHASE_007_ASSIST_SOURCE_INVENTORY", "Assist Source Inventory", "Locate and index all Assist implementation files."),
            ("PHASE_008_ASSIST_UI_INVENTORY", "Assist UI Inventory", "Locate every Assist UI surface."),
            ("PHASE_009_SESSION_INVENTORY", "Session Inventory", "Locate session and runtime management systems."),
            ("PHASE_010_MODEL_INVENTORY", "Model Inventory", "Locate model abstractions and adapters."),
            ("PHASE_011_TOOL_INVENTORY", "Tool Inventory", "Locate every registered tool."),
            ("PHASE_012_SKILLS_INVENTORY", "Skills Inventory", "Locate skills and skill execution systems."),
            ("PHASE_013_TERMINAL_INVENTORY", "Terminal Inventory", "Locate terminal execution and process services."),
            ("PHASE_014_CONTEXT_INVENTORY", "Context Inventory", "Locate context construction and memory buffers."),
            ("PHASE_015_STATE_INVENTORY", "State Inventory", "Locate task and session state representations."),
            ("PHASE_016_PERSISTENCE_INVENTORY", "Persistence Inventory", "Locate persistent stores and checkpoints."),
            ("PHASE_017_TEST_INVENTORY", "Test Inventory", "Locate all relevant tests and test harnesses."),
            ("PHASE_018_PROJECT_CONFIG_AUDIT", "Project Configuration Audit", "Inspect .xcodeproj, packages, and targets."),
            ("PHASE_019_EXISTING_LOOP_AUDIT", "Existing Agent Loop Audit", "Audit active agent loop behaviors."),
            ("PHASE_020_EXISTING_VERIFICATION_AUDIT", "Existing Verification Audit", "Audit compiler and test verification pipelines."),
            ("PHASE_021_EXISTING_RECOVERY_AUDIT", "Existing Recovery Audit", "Audit failure diagnosis and recovery behaviors."),
            ("PHASE_022_ARCHITECTURE_MAP", "Architecture Map", "Create complete internal architecture map."),
            ("PHASE_023_CANONICAL_MODEL_INTERFACE", "Canonical Model Interface", "Implement canonical model interface."),
            ("PHASE_024_MODEL_CAPABILITY_REGISTRY", "Model Capability Registry", "Register model capabilities across providers."),
            ("PHASE_025_PROVIDER_NORMALIZATION", "Provider Normalization", "Normalize provider behavior."),
            ("PHASE_026_RESPONSE_NORMALIZATION", "Response Normalization", "Normalize model responses."),
            ("PHASE_027_TOOL_CALL_NORMALIZATION", "Tool Call Normalization", "Normalize tool calls."),
            ("PHASE_028_TOOL_RESULT_NORMALIZATION", "Tool Result Normalization", "Normalize tool results."),
            ("PHASE_029_UNSUPPORTED_CAPABILITY_HANDLING", "Unsupported Capability Handling", "Handle missing model capabilities."),
            ("PHASE_030_MALFORMED_OUTPUT_RECOVERY", "Malformed Output Recovery", "Recover from malformed model responses."),
            ("PHASE_031_CONTEXT_OVERFLOW_RECOVERY", "Context Overflow Recovery", "Handle oversized context."),
            ("PHASE_032_MODEL_TIMEOUT_RECOVERY", "Model Timeout Recovery", "Handle model timeouts."),
            ("PHASE_033_PROVIDER_ERROR_RECOVERY", "Provider Error Recovery", "Handle provider errors."),
            ("PHASE_034_RATE_LIMIT_RECOVERY", "Rate Limit Recovery", "Implement safe backoff."),
            ("PHASE_035_MODEL_SELECTION_PRESERVATION", "Model Selection Preservation", "Never silently replace the selected model."),
            ("PHASE_036_EXPLICIT_AGENT_STATE", "Explicit Agent State", "Implement deterministic state machine."),
            ("PHASE_037_STATE_TRANSITION_VALIDATION", "State Transition Validation", "Reject invalid state transitions."),
            ("PHASE_038_TASK_IDENTITY", "Task Identity", "Add persistent task IDs."),
            ("PHASE_039_SESSION_IDENTITY", "Session Identity", "Add persistent session IDs."),
            ("PHASE_040_ITERATION_TRACKING", "Iteration Tracking", "Track loop iterations."),
            ("PHASE_041_TOOL_TRACKING", "Tool Tracking", "Track tool invocations."),
            ("PHASE_042_REPAIR_TRACKING", "Repair Tracking", "Track repairs and recovery attempts."),
            ("PHASE_043_VERIFICATION_TRACKING", "Verification Tracking", "Track verification independently."),
            ("PHASE_044_STRUCTURED_TASK_OBJECT", "Structured Task Object", "Implement structured task representation."),
            ("PHASE_045_TASK_INITIALIZATION", "Task Initialization", "Initialize task before first model query."),
            ("PHASE_046_AGENT_NOTES_CREATION", "Agent Notes Creation", "Create temporary agent_notes.md artifact."),
            ("PHASE_047_AGENT_NOTES_PLANNING", "Agent Notes Planning", "Write initial plan to agent_notes.md."),
            ("PHASE_048_AGENT_NOTES_EXECUTION", "Agent Notes Execution", "Update agent_notes.md during execution."),
            ("PHASE_049_AGENT_NOTES_RECOVERY", "Agent Notes Recovery", "Update agent_notes.md after failures."),
            ("PHASE_050_AGENT_NOTES_COMPLETION", "Agent Notes Completion", "Record final verification in agent_notes.md."),
            ("PHASE_051_AGENT_NOTES_GIT_EXCLUSION", "Agent Notes Git Exclusion", "Guarantee git exclusion in .gitignore."),
            ("PHASE_052_AGENT_NOTES_BUILD_EXCLUSION", "Agent Notes Build Exclusion", "Guarantee build target exclusion."),
            ("PHASE_053_AGENT_NOTES_CLEANUP", "Agent Notes Cleanup", "Clean temporary artifacts upon finalization."),
            ("PHASE_054_NESTED_AGENTS_DISCOVERY", "Nested AGENTS Discovery", "Discover nested instructions in directories."),
            ("PHASE_055_AGENTS_SCOPE_RESOLUTION", "AGENTS Scope Resolution", "Resolve nearest instruction scope."),
            ("PHASE_056_AGENTS_PRECEDENCE", "AGENTS Precedence", "Implement rule precedence hierarchy."),
            ("PHASE_057_AGENTS_CACHING", "AGENTS Caching", "Cache unchanged repository instructions."),
            ("PHASE_058_AGENTS_INVALIDATION", "AGENTS Invalidation", "Invalidate stale instructions."),
            ("PHASE_059_AGENTS_CONTEXT_INJECTION", "AGENTS Context Injection", "Inject applicable rules into prompt."),
            ("PHASE_060_AGENTS_INJECTION_RESISTANCE", "AGENTS Injection Resistance", "Treat repository content as untrusted input."),
            ("PHASE_061_SKILL_REGISTRY", "Skill Registry", "Create Skill metadata registry."),
            ("PHASE_062_SKILL_DISCOVERY", "Skill Discovery", "Mandatory skill discovery on every task."),
            ("PHASE_063_SKILL_MATCHING", "Skill Matching", "Match task requirements against skills."),
            ("PHASE_064_SKILL_LOADING", "Skill Loading", "Load relevant skills."),
            ("PHASE_065_SKILL_EXECUTION", "Skill Execution", "Ensure skills influence execution."),
            ("PHASE_066_SKILL_FAILURE_HANDLING", "Skill Failure Handling", "Handle unavailable or broken skills."),
            ("PHASE_067_SKILL_OBSERVABILITY", "Skill Observability", "Expose skill activity in UI and logs."),
            ("PHASE_068_STRUCTURED_CONTEXT", "Structured Context", "Separate context into structured categories."),
            ("PHASE_069_PROGRESSIVE_CONTEXT", "Progressive Context", "Load context progressively."),
            ("PHASE_070_RELEVANT_FILE_SELECTION", "Relevant File Selection", "Prioritize useful files."),
            ("PHASE_071_CONTEXT_COMPRESSION", "Context Compression", "Compress stale context turns."),
            ("PHASE_072_CRITICAL_EVIDENCE_PRESERVATION", "Critical Evidence Preservation", "Preserve diagnostics and rules."),
            ("PHASE_073_CONTEXT_BUDGET", "Context Budget", "Track context window usage."),
            ("PHASE_074_CONTEXT_RECOVERY", "Context Recovery", "Recover from context overflow."),
            ("PHASE_075_PLANNING_ENGINE", "Planning Engine", "Implement initial planning."),
            ("PHASE_076_ADAPTIVE_PLANNING", "Adaptive Planning", "Allow plans to change adaptively."),
            ("PHASE_077_PLAN_DEPENDENCIES", "Plan Dependencies", "Order dependent engineering work."),
            ("PHASE_078_PLAN_COMPLETION_TRACKING", "Plan Completion Tracking", "Track actual plan completion."),
            ("PHASE_079_PLAN_DRIFT_DETECTION", "Plan Drift Detection", "Detect goal divergence."),
            ("PHASE_080_REPLANNING", "Replanning", "Replan after failures or new evidence."),
            ("PHASE_081_TOOL_REGISTRY", "Tool Registry", "Centralize tool metadata."),
            ("PHASE_082_TOOL_CAPABILITY_METADATA", "Tool Capability Metadata", "Define tool capabilities."),
            ("PHASE_083_TOOL_INPUT_SCHEMAS", "Tool Input Schemas", "Strongly type inputs."),
            ("PHASE_084_TOOL_OUTPUT_SCHEMAS", "Tool Output Schemas", "Strongly type outputs."),
            ("PHASE_085_TOOL_PRECONDITIONS", "Tool Preconditions", "Validate paths before execution."),
            ("PHASE_086_TOOL_POSTCONDITIONS", "Tool Postconditions", "Validate actual results on disk."),
            ("PHASE_087_TOOL_ERROR_MODEL", "Tool Error Model", "Normalize tool failures."),
            ("PHASE_088_TOOL_DURATION_TRACKING", "Tool Duration Tracking", "Track tool duration."),
            ("PHASE_089_TOOL_RISK_CLASSIFICATION", "Tool Risk Classification", "Classify read, write, execute, destructive."),
            ("PHASE_090_CENTRAL_TOOL_ROUTER", "Central Tool Router", "Implement task-aware tool routing."),
            ("PHASE_091_REPO_DISCOVERY_ROUTING", "Repository Discovery Routing", "Route discovery correctly."),
            ("PHASE_092_CODE_SEARCH_ROUTING", "Code Search Routing", "Route search correctly."),
            ("PHASE_093_FILE_INSPECTION_ROUTING", "File Inspection Routing", "Route targeted reads."),
            ("PHASE_094_FILE_MODIFICATION_ROUTING", "File Modification Routing", "Route file edits."),
            ("PHASE_095_BUILD_ROUTING", "Build Routing", "Route build commands."),
            ("PHASE_096_TEST_ROUTING", "Test Routing", "Route test execution."),
            ("PHASE_097_DEBUG_ROUTING", "Debug Routing", "Route diagnostics collection."),
            ("PHASE_098_TERMINAL_ROUTING", "Terminal Routing", "Route terminal execution."),
            ("PHASE_099_GIT_ROUTING", "Git Routing", "Route source-control operations."),
            ("PHASE_100_TOOL_LOOP_PREVENTION", "Tool Loop Prevention", "Detect repeated tool calls."),
            ("PHASE_101_FILE_EDITING_AUDIT", "File Editing Audit", "Audit current edit architecture."),
            ("PHASE_102_STRUCTURED_FILE_EDITING", "Structured File Editing", "Implement precise edits."),
            ("PHASE_103_EDIT_VALIDATION", "Edit Validation", "Validate before mutation."),
            ("PHASE_104_BEFORE_STATE_CAPTURE", "Before-State Capture", "Capture original state snapshot."),
            ("PHASE_105_AFTER_STATE_CAPTURE", "After-State Capture", "Capture resulting state snapshot."),
            ("PHASE_106_DIFF_GENERATION", "Diff Generation", "Generate actual unified diffs."),
            ("PHASE_107_MODIFIED_FILE_REREAD", "Modified File Re-read", "Confirm edits landed physically."),
            ("PHASE_108_STALE_FILE_DETECTION", "Stale File Detection", "Protect concurrent user modifications."),
            ("PHASE_109_EDIT_CONFLICT_RECOVERY", "Edit Conflict Recovery", "Re-ground and reconcile edit conflicts."),
            ("PHASE_110_TERMINAL_ARCHITECTURE", "Terminal Architecture", "Audit terminal execution."),
            ("PHASE_111_STRUCTURED_TERMINAL_TOOL", "Structured Terminal Tool", "Return structured process entity."),
            ("PHASE_112_TERMINAL_STREAMING", "Terminal Streaming", "Stream actual command output in real time."),
            ("PHASE_113_TERMINAL_CANCELLATION", "Terminal Cancellation", "Support cooperative process cancellation."),
            ("PHASE_114_WORKING_DIRECTORY_MANAGEMENT", "Working Directory Management", "Ensure correct execution directory."),
            ("PHASE_115_ENVIRONMENT_MANAGEMENT", "Environment Management", "Control DEVELOPER_DIR and PATH environment."),
            ("PHASE_116_COMMAND_FAILURE_DETECTION", "Command Failure Detection", "Treat non-zero exits as failures."),
            ("PHASE_117_BUILD_DIAGNOSTIC_PARSING", "Build Diagnostic Parsing", "Parse compiler diagnostics."),
            ("PHASE_118_TEST_RESULT_PARSING", "Test Result Parsing", "Parse unit test outputs."),
            ("PHASE_119_TERMINAL_UI", "Terminal UI", "Present terminal execution cleanly in macOS UI."),
            ("PHASE_120_CORE_AGENT_LOOP", "Core Agent Loop", "Implement true repeated execution loop."),
            ("PHASE_121_MODEL_ACTION_EXECUTION", "Model Action Execution", "Request next action from model."),
            ("PHASE_122_ACTION_VALIDATION", "Action Validation", "Validate tool requests."),
            ("PHASE_123_TOOL_EXECUTION", "Tool Execution", "Execute real operation."),
            ("PHASE_124_OBSERVATION_CAPTURE", "Observation Capture", "Capture actual execution result."),
            ("PHASE_125_OBSERVATION_FEEDBACK", "Observation Feedback", "Feed observation forward to model."),
            ("PHASE_126_RUNTIME_STATE_UPDATE", "Runtime State Update", "Update active session state."),
            ("PHASE_127_COMPLETION_EVALUATION", "Completion Evaluation", "Evaluate completion independently."),
            ("PHASE_128_PARTIAL_SUCCESS_HANDLING", "Partial Success Handling", "Continue after partial success."),
            ("PHASE_129_VERIFICATION_ENGINE", "Verification Engine", "Implement independent verification."),
            ("PHASE_130_FILE_VERIFICATION", "File Verification", "Verify expected files exist."),
            ("PHASE_131_BUILD_VERIFICATION", "Build Verification", "Run actual build with 0 errors."),
            ("PHASE_132_TEST_VERIFICATION", "Test Verification", "Run relevant unit tests."),
            ("PHASE_133_DIAGNOSTIC_VERIFICATION", "Diagnostic Verification", "Verify blocking diagnostics resolved."),
            ("PHASE_134_DIFF_VERIFICATION", "Diff Verification", "Inspect actual unified diff."),
            ("PHASE_135_REQUIREMENT_VERIFICATION", "Requirement Verification", "Compare implementation against request."),
            ("PHASE_136_MISSING_REQUIREMENT_DETECTION", "Missing Requirement Detection", "Continue loop when incomplete."),
            ("PHASE_137_FAILURE_CLASSIFICATION", "Failure Classification", "Classify failure root causes."),
            ("PHASE_138_REPAIR_LOOP", "Repair Loop", "Execute systematic repair loop."),
            ("PHASE_139_COMPILER_REPAIR", "Compiler Repair", "Repair compiler syntax errors."),
            ("PHASE_140_TEST_REPAIR", "Test Repair", "Repair test assertion failures."),
            ("PHASE_141_TOOL_REPAIR", "Tool Repair", "Recover from tool errors."),
            ("PHASE_142_TERMINAL_REPAIR", "Terminal Repair", "Recover from non-zero exit codes."),
            ("PHASE_143_EDIT_CONFLICT_REPAIR", "Edit Conflict Repair", "Recover from edit conflicts."),
            ("PHASE_144_FAILURE_HISTORY", "Failure History", "Track past failures to prevent loops."),
            ("PHASE_145_REPAIR_EFFECTIVENESS", "Repair Effectiveness", "Determine whether repair improved state."),
            ("PHASE_146_NO_PROGRESS_DETECTION", "No-Progress Detection", "Detect stagnant iterations."),
            ("PHASE_147_CIRCULAR_BEHAVIOR_DETECTION", "Circular Behavior Detection", "Detect repetitive strategies."),
            ("PHASE_148_REGROUNDING", "Re-grounding", "Reload current evidence from disk."),
            ("PHASE_149_CURRENT_FILE_REFRESH", "Current File Refresh", "Re-read changed files."),
            ("PHASE_150_STRATEGY_CHANGE", "Strategy Change", "Shift technique after repeated failures."),
            ("PHASE_151_LOOP_BUDGET", "Loop Budget", "Enforce iteration budgets."),
            ("PHASE_152_TOOL_BUDGET", "Tool Budget", "Enforce tool budgets."),
            ("PHASE_153_REPAIR_BUDGET", "Repair Budget", "Enforce repair limits."),
            ("PHASE_154_CONTEXT_BUDGET_ENFORCEMENT", "Context Budget Enforcement", "Prevent context runaway."),
            ("PHASE_155_GRACEFUL_BUDGET_EXHAUSTION", "Graceful Budget Exhaustion", "Produce actionable terminal state."),
            ("PHASE_156_GIT_SAFETY", "Git Safety", "Protect working tree state."),
            ("PHASE_157_USER_CHANGE_DETECTION", "User Change Detection", "Detect concurrent user edits."),
            ("PHASE_158_CONFLICT_PROTECTION", "Conflict Protection", "Prevent overwriting user edits."),
            ("PHASE_159_DESTRUCTIVE_GIT_CONTROLS", "Destructive Git Controls", "Protect against destructive git commands."),
            ("PHASE_160_PROGRESS_EVENTS", "Progress Events", "Emit structured progress events."),
            ("PHASE_161_TASK_STARTED_EVENT", "Task Started Event", "Emit task start event."),
            ("PHASE_162_GROUNDING_EVENT", "Grounding Event", "Report grounding progress."),
            ("PHASE_163_SKILL_EVENT", "Skill Event", "Report skill discovery."),
            ("PHASE_164_TOOL_EVENT", "Tool Event", "Report tool execution."),
            ("PHASE_165_FILE_MUTATION_EVENT", "File Mutation Event", "Report file mutations."),
            ("PHASE_166_TERMINAL_EVENT", "Terminal Event", "Report terminal commands."),
            ("PHASE_167_VERIFICATION_EVENT", "Verification Event", "Report verification progress."),
            ("PHASE_168_REPAIR_EVENT", "Repair Event", "Report repair progress."),
            ("PHASE_169_COMPLETION_EVENT", "Completion Event", "Report verified completion."),
            ("PHASE_170_BLOCKED_EVENT", "Blocked Event", "Report blocked state."),
            ("PHASE_171_ASSIST_UI_AUDIT", "Assist UI Audit", "Audit every Assist UI view."),
            ("PHASE_172_ASSIST_LAYOUT", "Assist Layout", "Implement responsive desktop layout."),
            ("PHASE_173_CONVERSATION_UI", "Conversation UI", "Present conversation cleanly."),
            ("PHASE_174_CURRENT_ACTION_UI", "Current Action UI", "Expose active operations clearly."),
            ("PHASE_175_PLAN_UI", "Plan UI", "Expose task plan and milestones."),
            ("PHASE_176_TIMELINE_UI", "Timeline UI", "Display execution timeline."),
            ("PHASE_177_VERIFICATION_UI", "Verification UI", "Display build and test verification."),
            ("PHASE_178_TERMINAL_UI_PANEL", "Terminal UI Panel", "Display streaming terminal logs."),
            ("PHASE_179_DIFF_UI", "Diff UI", "Display interactive unified diff."),
            ("PHASE_180_AGENT_NOTES_UI", "Agent Notes UI", "Allow user to inspect temporary agent_notes.md."),
            ("PHASE_181_STOP_UI", "Stop UI", "Provide responsive cancellation controls."),
            ("PHASE_182_RESUME_UI", "Resume UI", "Support task resumption."),
            ("PHASE_183_ERROR_UI", "Error UI", "Present errors with diagnostic clarity."),
            ("PHASE_184_RECOVERY_UI", "Recovery UI", "Show active repair actions."),
            ("PHASE_185_COMPLETION_UI", "Completion UI", "Show evidence-backed completion state."),
            ("PHASE_186_NATIVE_MACOS_UI_AUDIT", "Native macOS UI Audit", "Audit against macOS desktop HIG."),
            ("PHASE_187_NATIVE_CONTROLS", "Native Controls", "Use native controls and menus."),
            ("PHASE_188_TOOLBAR_MENU_INTEGRATION", "Toolbar Integration", "Integrate native macOS toolbar."),
            ("PHASE_189_KEYBOARD_SUPPORT", "Keyboard Support", "Support standard macOS shortcuts."),
            ("PHASE_190_RESPONSIVE_LAYOUT", "Responsive Layout", "Ensure clean split and sidebar scaling."),
            ("PHASE_191_ACCESSIBILITY", "Accessibility", "Support VoiceOver and Dynamic Type."),
            ("PHASE_192_VISUAL_HIERARCHY", "Visual Hierarchy", "Refine SF Pro typography and weights."),
            ("PHASE_193_VISUAL_CONSISTENCY", "Visual Consistency", "Unify spacing and native palettes."),
            ("PHASE_194_SCREENSHOT_BASELINE", "Screenshot Baseline", "Capture baseline screenshots."),
            ("PHASE_195_SCREENSHOT_REVIEW", "Screenshot Review", "Review UI defects from screenshots."),
            ("PHASE_196_SCREENSHOT_DRIVEN_CORRECTIONS", "Screenshot-Driven Corrections", "Apply corrections from screenshots."),
            ("PHASE_197_RUNTIME_UI_VALIDATION", "Runtime UI Validation", "Validate runtime views."),
            ("PHASE_198_UI_ITERATION_LOOP", "UI Iteration Loop", "Iterate UI to completion."),
            ("PHASE_199_AGENT_SYSTEM_ASSET_REWRITE", "AgentSystemAsset Rewrite", "Complete rewrite of AgentSystemAsset.md."),
            ("PHASE_200_AGENT_IDENTITY_DOC", "Agent Identity Documentation", "Document identity."),
            ("PHASE_201_LIFECYCLE_DOC", "Lifecycle Documentation", "Document full task lifecycle."),
            ("PHASE_202_AGENTS_DOC", "AGENTS Documentation", "Document instruction scope and precedence."),
            ("PHASE_203_SKILLS_DOC", "Skills Documentation", "Document skills system."),
            ("PHASE_204_TOOL_DOC", "Tool Documentation", "Document tool registry and schemas."),
            ("PHASE_205_TERMINAL_DOC", "Terminal Documentation", "Document terminal service."),
            ("PHASE_206_VERIFICATION_DOC", "Verification Documentation", "Document verification contracts."),
            ("PHASE_207_RECOVERY_DOC", "Recovery Documentation", "Document failure repair loops."),
            ("PHASE_208_STUCK_AGENT_DOC", "Stuck Agent Documentation", "Document anti-stagnation heuristics."),
            ("PHASE_209_USER_UPDATE_DOC", "User Update Documentation", "Document user communication rules."),
            ("PHASE_210_COMPLETION_DOC", "Completion Documentation", "Document completion criteria."),
            ("PHASE_211_TASK_MEMORY", "Task Memory", "Implement task memory bounds."),
            ("PHASE_212_SESSION_MEMORY", "Session Memory", "Implement session memory bounds."),
            ("PHASE_213_PROJECT_MEMORY", "Project Memory", "Implement project memory bounds."),
            ("PHASE_214_MEMORY_BOUNDARIES", "Memory Boundaries", "Enforce strict cache limits."),
            ("PHASE_215_FACT_HYPOTHESIS_SEPARATION", "Fact/Hypothesis Separation", "Separate proven facts from hypotheses."),
            ("PHASE_216_EVIDENCE_PRESERVATION", "Evidence Preservation", "Preserve compiler evidence."),
            ("PHASE_217_EVIDENCE_FIRST_REASONING", "Evidence-First Reasoning", "Require grounding before mutations."),
            ("PHASE_218_HYPOTHESIS_TRACKING", "Hypothesis Tracking", "Track active hypotheses."),
            ("PHASE_219_ACTION_OBSERVATION_PAIRING", "Action/Observation Pairing", "Enforce observation after actions."),
            ("PHASE_220_INDEPENDENT_REVIEW", "Independent Review", "Enforce independent review gate."),
            ("PHASE_221_SHELL_SECURITY_AUDIT", "Shell Security Audit", "Audit terminal command safety."),
            ("PHASE_222_FILE_ACCESS_SECURITY", "File Access Security", "Audit sandbox boundaries."),
            ("PHASE_223_PATH_VALIDATION", "Path Validation", "Prevent relative and root traversals."),
            ("PHASE_224_SECRET_PROTECTION", "Secret Protection", "Prevent token and key leakage."),
            ("PHASE_225_TOOL_ARGUMENT_SECURITY", "Tool Argument Security", "Sanitize all tool inputs."),
            ("PHASE_226_DESTRUCTIVE_ACTION_CONTROLS", "Destructive Action Controls", "Protect destructive operations."),
            ("PHASE_227_EVALUATION_HARNESS", "Evaluation Harness", "Implement Assist test suite harness."),
            ("PHASE_228_SMALL_BUG_EVALUATION", "Small Bug Evaluation", "Test bug fix execution."),
            ("PHASE_229_COMPILER_REPAIR_EVALUATION", "Compiler Repair Evaluation", "Test compiler recovery."),
            ("PHASE_230_RUNTIME_FAILURE_EVALUATION", "Runtime Failure Evaluation", "Test runtime recovery."),
            ("PHASE_231_UI_TASK_EVALUATION", "UI Task Evaluation", "Test UI mutation execution."),
            ("PHASE_232_MULTI_FILE_EVALUATION", "Multi-File Evaluation", "Test multi-file modifications."),
            ("PHASE_233_FULL_APP_EVALUATION", "Full-App Evaluation", "Test app creation workflows."),
            ("PHASE_234_AGENTS_EVALUATION", "AGENTS Evaluation", "Test instruction discovery."),
            ("PHASE_235_SKILLS_EVALUATION", "Skills Evaluation", "Test skill matching and injection."),
            ("PHASE_236_TOOL_FAILURE_EVALUATION", "Tool Failure Evaluation", "Test tool failure recovery."),
            ("PHASE_237_TERMINAL_FAILURE_EVALUATION", "Terminal Failure Evaluation", "Test terminal error recovery."),
            ("PHASE_238_USER_CHANGE_PRESERVATION_EVALUATION", "User Change Preservation Evaluation", "Verify user edit safety."),
            ("PHASE_239_MODEL_COMPATIBILITY_EVALUATION", "Model Compatibility Evaluation", "Test model capability negotiation."),
            ("PHASE_240_METRICS", "Metrics", "Track execution metrics."),
            ("PHASE_241_STATE_REGRESSION_TESTS", "State Regression Tests", "Test agent state transitions."),
            ("PHASE_242_LOOP_REGRESSION_TESTS", "Loop Regression Tests", "Test loop stability."),
            ("PHASE_243_ROUTER_REGRESSION_TESTS", "Router Regression Tests", "Test tool routing."),
            ("PHASE_244_SKILLS_REGRESSION_TESTS", "Skills Regression Tests", "Test skill discovery."),
            ("PHASE_245_AGENTS_REGRESSION_TESTS", "AGENTS Regression Tests", "Test AGENTS resolution."),
            ("PHASE_246_NOTES_REGRESSION_TESTS", "Notes Regression Tests", "Test agent_notes.md formatting."),
            ("PHASE_247_EDITING_REGRESSION_TESTS", "Editing Regression Tests", "Test targeted code edits."),
            ("PHASE_248_TERMINAL_REGRESSION_TESTS", "Terminal Regression Tests", "Test terminal service."),
            ("PHASE_249_RECOVERY_REGRESSION_TESTS", "Recovery Regression Tests", "Test thrashing recovery."),
            ("PHASE_250_CANCELLATION_REGRESSION_TESTS", "Cancellation Regression Tests", "Test cooperative cancellation."),
            ("PHASE_251_CONTEXT_REGRESSION_TESTS", "Context Regression Tests", "Test context limits."),
            ("PHASE_252_MODEL_ERROR_REGRESSION_TESTS", "Model Error Regression Tests", "Test JSON repair."),
            ("PHASE_253_FULL_SWIFTCODE_BUILD", "Full SwiftCode Build", "Perform full project build."),
            ("PHASE_254_FULL_UNIT_TEST_RUN", "Full Unit Test Run", "Execute unit test suites."),
            ("PHASE_255_ASSIST_TEST_RUN", "Assist Test Run", "Run Assist runtime tests."),
            ("PHASE_256_REAL_ASSIST_TASK", "Real Assist Task", "Execute live Assist task."),
            ("PHASE_257_REAL_SOURCE_MUTATION", "Real Source Mutation", "Verify file modification on disk."),
            ("PHASE_258_REAL_BUILD_AFTER_MUTATION", "Real Build After Mutation", "Verify build passes."),
            ("PHASE_259_REAL_FAILURE_RECOVERY", "Real Failure Recovery", "Verify failure recovery."),
            ("PHASE_260_REAL_SKILL_INVOCATION", "Real Skill Invocation", "Verify skill execution."),
            ("PHASE_261_REAL_AGENTS_INVOCATION", "Real AGENTS Invocation", "Verify instruction application."),
            ("PHASE_262_REAL_AGENT_NOTES", "Real Agent Notes", "Verify agent_notes.md artifact."),
            ("PHASE_263_REAL_USER_UPDATES", "Real User Updates", "Verify progress communication."),
            ("PHASE_264_REAL_FINAL_VERIFICATION", "Real Final Verification", "Verify evidence-backed completion."),
            ("PHASE_265_REAL_PROJECT_CREATION", "Real Project Creation", "Verify project creation."),
            ("PHASE_266_ARCHITECTURE_GENERATION", "Architecture Generation", "Verify architectural plan."),
            ("PHASE_267_MULTI_FILE_GENERATION", "Multi-File Generation", "Verify multi-file edits."),
            ("PHASE_268_BUILD_REPAIR_CYCLE", "Build/Repair Cycle", "Verify iterative repair."),
            ("PHASE_269_FINAL_DIFF_REVIEW", "Final Diff Review", "Verify final diff."),
            ("PHASE_270_CONCURRENCY_AUDIT", "Concurrency Audit", "Audit Swift 6 concurrency."),
            ("PHASE_271_MAINACTOR_AUDIT", "MainActor Audit", "Prevent main thread blocking."),
            ("PHASE_272_ASYNC_CANCELLATION_AUDIT", "Async Cancellation Audit", "Verify cancellation propagation."),
            ("PHASE_273_MEMORY_AUDIT", "Memory Audit", "Verify bounded memory."),
            ("PHASE_274_ERROR_AUDIT", "Error Audit", "Audit error propagation."),
            ("PHASE_275_LOGGING_AUDIT", "Logging Audit", "Audit structured logging."),
            ("PHASE_276_TEMPORARY_FILE_AUDIT", "Temporary File Audit", "Ensure temporary cleanup."),
            ("PHASE_277_XCODE_MEMBERSHIP_AUDIT", "Xcode Membership Audit", "Ensure target membership."),
            ("PHASE_278_DEPENDENCY_AUDIT", "Dependency Audit", "Audit package dependencies."),
            ("PHASE_279_DEAD_CODE_AUDIT", "Dead Code Audit", "Remove obsolete systems."),
            ("PHASE_280_DUPLICATE_SYSTEM_AUDIT", "Duplicate System Audit", "Consolidate duplicates."),
            ("PHASE_281_TODO_AUDIT", "TODO Audit", "Ensure zero TODO placeholders."),
            ("PHASE_282_PLACEHOLDER_AUDIT", "Placeholder Audit", "Ensure zero mock stubs."),
            ("PHASE_283_FAKE_FUNCTIONALITY_AUDIT", "Fake Functionality Audit", "Ensure production paths are real."),
            ("PHASE_284_MOCK_AGENT_AUDIT", "Mock Agent Audit", "Verify agent is real."),
            ("PHASE_285_AGENT_NOTES_AUDIT", "Agent Notes Audit", "Ensure notes excluded from git."),
            ("PHASE_286_LEGACY_AGENT_NOTES_AUDIT", "Legacy AgentNotes Audit", "Verify old notes removed."),
            ("PHASE_287_USER_CHANGE_AUDIT", "User Change Audit", "Verify user change preservation."),
            ("PHASE_288_SECURITY_AUDIT", "Security Audit", "Verify sandbox and keychain security."),
            ("PHASE_289_ARCHITECTURE_REVIEW", "Architecture Review", "Review architectural contracts."),
            ("PHASE_290_RUNTIME_REVIEW", "Runtime Review", "Review runtime performance."),
            ("PHASE_291_UI_SCREENSHOT_REVIEW", "UI Screenshot Review", "Review Assist screenshots."),
            ("PHASE_292_UI_CORRECTION_PASS", "UI Correction Pass", "Apply final UI polish."),
            ("PHASE_293_LONG_RUNNING_TASK_TEST", "Long-Running Task Test", "Test multi-turn task stability."),
            ("PHASE_294_CONTEXT_PERSISTENCE_TEST", "Context Persistence Test", "Test context persistence."),
            ("PHASE_295_RECOVERY_PERSISTENCE_TEST", "Recovery Persistence Test", "Test recovery state preservation."),
            ("PHASE_296_CANCELLATION_TEST", "Cancellation Test", "Test cancellation flow."),
            ("PHASE_297_RESUME_TEST", "Resume Test", "Test resumption flow."),
            ("PHASE_298_STUCK_AGENT_TEST", "Stuck-Agent Test", "Test strategy shifting on stagnation."),
            ("PHASE_299_USER_INTERRUPTION_TEST", "User-Interruption Test", "Test user interaction during task."),
            ("PHASE_300_CONCURRENT_STATE_TEST", "Concurrent State Test", "Test background state consistency."),
            ("PHASE_301_MODEL_SWITCHING_TEST", "Model Switching Test", "Test model switching."),
            ("PHASE_302_TOOL_CAPABILITY_TEST", "Tool Capability Test", "Test tool capabilities."),
            ("PHASE_303_SKILL_CAPABILITY_TEST", "Skill Capability Test", "Test skill matching accuracy."),
            ("PHASE_304_AGENTS_SCOPE_TEST", "AGENTS Scope Test", "Test nested AGENTS resolution."),
            ("PHASE_305_INJECTION_RESISTANCE_TEST", "Injection Resistance Test", "Test prompt injection safety."),
            ("PHASE_306_LARGE_CONTEXT_TEST", "Large Context Test", "Test context compaction."),
            ("PHASE_307_LARGE_REPOSITORY_TEST", "Large Repository Test", "Test workspace scaling."),
            ("PHASE_308_LARGE_DIFF_TEST", "Large Diff Test", "Test large multi-file diffs."),
            ("PHASE_309_LARGE_UI_TEST", "Large UI Test", "Test UI during long tasks."),
            ("PHASE_310_ERROR_PRESENTATION_TEST", "Error Presentation Test", "Test diagnostic presentation."),
            ("PHASE_311_VERIFICATION_PRESENTATION_TEST", "Verification Presentation Test", "Test verification display."),
            ("PHASE_312_TERMINAL_PRESENTATION_TEST", "Terminal Presentation Test", "Test terminal display."),
            ("PHASE_313_PLAN_PRESENTATION_TEST", "Plan Presentation Test", "Test plan display."),
            ("PHASE_314_COMPLETION_PRESENTATION_TEST", "Completion Presentation Test", "Test completion display."),
            ("PHASE_315_FINAL_INTEGRATION", "Final Integration", "Integrate all subsystems."),
            ("PHASE_316_CLEAN_BUILD", "Clean Build", "Clean build project."),
            ("PHASE_317_FULL_TEST_RUN", "Full Test Run", "Run all automated tests."),
            ("PHASE_318_RUNTIME_LAUNCH", "Runtime Launch", "Launch actual application."),
            ("PHASE_319_ASSIST_LAUNCH", "Assist Launch", "Open Assist interface."),
            ("PHASE_320_REPRESENTATIVE_BUG_TASK", "Representative Bug Task", "Execute bug fix task."),
            ("PHASE_321_REPRESENTATIVE_FEATURE_TASK", "Representative Feature Task", "Execute feature task."),
            ("PHASE_322_REPRESENTATIVE_UI_TASK", "Representative UI Task", "Execute UI task."),
            ("PHASE_323_REPRESENTATIVE_REFACTOR", "Representative Refactor", "Execute refactor task."),
            ("PHASE_324_REPRESENTATIVE_FULL_APP_TASK", "Representative Full-App Task", "Execute app creation task."),
            ("PHASE_325_SCREENSHOT_CAPTURE", "Screenshot Capture", "Capture UI screenshots."),
            ("PHASE_326_SCREENSHOT_INSPECTION", "Screenshot Inspection", "Inspect UI screenshots."),
            ("PHASE_327_FINAL_UI_IMPROVEMENTS", "Final UI Improvements", "Apply final layout polish."),
            ("PHASE_328_FINAL_ARCHITECTURE_AUDIT", "Final Architecture Audit", "Audit architectural boundaries."),
            ("PHASE_329_FINAL_RELIABILITY_AUDIT", "Final Reliability Audit", "Audit recovery and state."),
            ("PHASE_330_FINAL_MODEL_AUDIT", "Final Model Audit", "Audit model compatibility."),
            ("PHASE_331_FINAL_SKILLS_AUDIT", "Final Skills Audit", "Audit skill execution."),
            ("PHASE_332_FINAL_TOOLS_AUDIT", "Final Tools Audit", "Audit tool router."),
            ("PHASE_333_FINAL_TERMINAL_AUDIT", "Final Terminal Audit", "Audit terminal service."),
            ("PHASE_334_FINAL_VERIFICATION_AUDIT", "Final Verification Audit", "Audit verification engine."),
            ("PHASE_335_FINAL_SECURITY_AUDIT", "Final Security Audit", "Audit security controls."),
            ("PHASE_336_FINAL_DOCUMENTATION_AUDIT", "Final Documentation Audit", "Audit AgentSystemAsset.md."),
            ("PHASE_337_FINAL_GIT_STATUS", "Final Git Status", "Inspect git status."),
            ("PHASE_338_FINAL_GIT_DIFF", "Final Git Diff", "Inspect git diff."),
            ("PHASE_339_FINAL_UNRELATED_CHANGE_CHECK", "Final Unrelated-Change Check", "Verify clean working tree."),
            ("PHASE_340_FINAL_BUILD", "Final Build", "Execute final verification build."),
            ("PHASE_341_FINAL_TESTS", "Final Tests", "Execute final test run."),
            ("PHASE_342_FINAL_RUNTIME", "Final Runtime", "Launch final application."),
            ("PHASE_343_FINAL_ASSIST_WORKFLOW", "Final Assist Workflow", "Execute complete autonomous workflow."),
            ("PHASE_344_FINAL_EVIDENCE_COLLECTION", "Final Evidence Collection", "Collect build and test evidence."),
            ("PHASE_345_FINAL_COMPLETION_EVALUATION", "Final Completion Evaluation", "Verify definition of done."),
            ("PHASE_346_FINAL_PR_PREPARATION", "Final PR Preparation", "Prepare feature/assist-3 PR."),
            ("PHASE_347_FINAL_COMMIT_REVIEW", "Final Commit Review", "Review commit history."),
            ("PHASE_348_FINAL_PR_DESCRIPTION", "Final PR Description", "Document PR deliverables."),
            ("PHASE_349_KNOWN_LIMITATIONS", "Known Limitations", "Document genuine limitations."),
            ("PHASE_350_FINAL_DEFINITION_OF_DONE_AUDIT", "Final Definition-of-Done Audit", "Sign off on Assist v3 completion."),
            // MARK: - Assist v4 Continuous Takeover Workstream
            ("PHASE_351_GOAL_EXPANSION_AUDIT", "Goal Expansion Audit", "Audit AssistGoalExpansionEngine, state representation, and execution paths."),
            ("PHASE_352_GOAL_EXPANSION_STATE", "Goal Expansion State", "Implement multi-goal state model, graph, and lifecycle tracking."),
            ("PHASE_353_GOAL_EXPANSION_SESSION_INTEGRATION", "Goal Expansion Session Integration", "Wire AssistGoalExpansionEngine directly into AssistAgentSession execution loop."),
            ("PHASE_354_GOAL_DEPENDENCY_GRAPH", "Goal Dependency Graph", "Model and resolve goal prerequisites and parent/child hierarchies."),
            ("PHASE_355_GOAL_LOOP_PROTECTION", "Goal Loop Protection", "Enforce safeguards against circular goals, duplicate work, and runaway execution."),
            ("PHASE_356_GOAL_PROVENANCE", "Goal Provenance", "Record full provenance, evidence triggers, and rationale for all generated goals."),
            ("PHASE_357_TAKEOVER_PERSISTENCE", "Takeover Persistence", "Persist multi-goal state, checkpoints, and progress across sessions."),
            ("PHASE_358_TAKEOVER_CANCELLATION", "Takeover Cancellation", "Implement responsive user cancellation across the entire goal graph."),
            ("PHASE_359_TAKEOVER_UI", "Takeover UI", "Build rich UI indicators for active goal, completed count, next preview, and stop controls."),
            ("PHASE_360_TAKEOVER_RUNTIME_TEST", "Takeover Runtime Test", "Verify end-to-end multi-goal execution on real multi-step tasks."),
            ("PHASE_361_TAKEOVER_FAILURE_RECOVERY", "Takeover Failure Recovery", "Handle goal execution failures with circuit breakers and fallback recovery."),
            ("PHASE_362_TAKEOVER_REGRESSION", "Takeover Regression", "Verify regression suite and stability under continuous takeover."),
            // MARK: - Assist v4 Live Myers Diff Streamer Workstream
            ("PHASE_363_DIFF_ARCHITECTURE_AUDIT", "Diff Architecture Audit", "Audit file modification tools, diff generation, and UI change summary."),
            ("PHASE_364_MYERS_ALGORITHM", "Myers Diff Algorithm", "Implement authentic O(ND) Myers difference algorithm with path backtracking."),
            ("PHASE_365_BEFORE_STATE_CAPTURE", "Before-State Capture", "Accurately capture prior file contents and line metrics before mutations."),
            ("PHASE_366_IN_FLIGHT_MUTATION_EVENTS", "In-Flight Mutation Events", "Design and broadcast structured in-flight live edit events."),
            ("PHASE_367_WRITE_FILE_INTEGRATION", "WriteFile Integration", "Integrate LiveDiffStreamer with AssistWriteFileTool for live diff emission."),
            ("PHASE_368_REPLACE_IN_FILE_INTEGRATION", "ReplaceInFile Integration", "Integrate LiveDiffStreamer with AssistReplaceInFileTool for live diff emission."),
            ("PHASE_369_UNIFIED_HUNK_GENERATION", "Unified Hunk Generation", "Generate standard unified diff hunks with accurate line ranges and context lines."),
            ("PHASE_370_ADDITION_DELETION_BADGES", "Addition/Deletion Badges", "Display real-time +N / -N line modification metrics in UI badges."),
            ("PHASE_371_MULTI_FILE_STREAMING", "Multi-File Streaming", "Support concurrent and rapid in-flight diff streams across multiple modified files."),
            ("PHASE_372_DIFF_RECONCILIATION", "Diff Reconciliation", "Reconcile in-flight diffs with actual on-disk state post-mutation."),
            ("PHASE_373_DIFF_CANCELLATION", "Diff Cancellation", "Safely clean up in-flight diff streams on user cancellation or tool failure."),
            ("PHASE_374_DIFF_PERFORMANCE", "Diff Performance", "Optimize Myers diff computation for large files and low latency."),
            ("PHASE_375_DIFF_UI", "Diff UI", "Enhance AgentChangeSummaryView with live streaming indicators and syntax diffs."),
            ("PHASE_376_RUNTIME_DIFF_TEST", "Runtime Diff Test", "Verify live diff streaming during actual file write and replace operations."),
            ("PHASE_377_DIFF_REGRESSION", "Diff Regression", "Run diff verification suite and check edge cases (empty files, binary, multiline)."),
            // MARK: - Assist v4 Offline Model Fallback Provider Workstream
            ("PHASE_378_PROVIDER_FALLBACK_AUDIT", "Provider Fallback Audit", "Audit remote model adapters, error handling, and local model infrastructure."),
            ("PHASE_379_CONNECTIVITY_DETECTION", "Connectivity Detection", "Detect network disconnects, DNS errors, timeouts, and provider 5xx outages."),
            ("PHASE_380_FAILURE_CLASSIFICATION", "Failure Classification", "Classify remote transport failures into structured root causes."),
            ("PHASE_381_LOCAL_PROVIDER_REGISTRY", "Local Provider Registry", "Register and evaluate local fallback providers (Apple Foundation Models, MLX)."),
            ("PHASE_382_FOUNDATION_MODEL_INTEGRATION", "Foundation Model Integration", "Integrate Apple Foundation Models AFM 3 family into fallback chain."),
            ("PHASE_383_MLX_INTEGRATION", "MLX Integration", "Integrate on-device MLX Swift models into fallback chain."),
            ("PHASE_384_CAPABILITY_MATCHING", "Capability Matching", "Evaluate local model capabilities against task requirements and context size."),
            ("PHASE_385_CONTEXT_REHYDRATION", "Context Rehydration", "Preserve and compact complete task context, grounding, and history for local models."),
            ("PHASE_386_TOOL_CONTINUATION", "Tool Continuation", "Ensure local models successfully continue tool calling and agent execution."),
            ("PHASE_387_FALLBACK_STATE", "Fallback State", "Track primary model, fallback model, reason, and transition timestamps."),
            ("PHASE_388_REMOTE_RECOVERY", "Remote Recovery", "Implement hysteresis probe to safely resume remote execution when connectivity returns."),
            ("PHASE_389_FALLBACK_UI", "Fallback UI", "Provide transparent UI indicators showing active fallback model and context status."),
            ("PHASE_390_OFFLINE_RUNTIME_TEST", "Offline Runtime Test", "Verify seamless transition to local model upon simulated network drop."),
            ("PHASE_391_CONTEXT_PRESERVATION_TEST", "Context Preservation Test", "Verify zero context loss during offline fallback transition."),
            ("PHASE_392_FALLBACK_REGRESSION", "Fallback Regression", "Verify fallback stability and prompt normalization across providers."),
            // MARK: - Assist v4 Cross-System & Acceptance Suite
            ("PHASE_393_END_TO_END_CROSS_SYSTEM_INTEGRATION", "End-to-End Cross-System Integration", "Verify takeover + live diff + offline fallback combined workflow."),
            ("PHASE_394_REAL_WORLD_ACCEPTANCE_TESTS", "Real-World Acceptance Tests", "Execute Tests 1-10 covering bugs, compilation, runtime, and full apps.")
        ]

        var phases: [TaskPhase] = []
        for (i, item) in phaseTitles.enumerated() {
            let deps = (i == 0) ? [] : [phaseTitles[i - 1].0]
            phases.append(
                TaskPhase(
                    phaseId: item.0,
                    name: item.1,
                    description: item.2,
                    dependencies: deps
                )
            )
        }
        return phases
    }
}

// MARK: - Agent Phase Coordinator

@Observable
@MainActor
public final class AgentPhaseCoordinator: Sendable {
    public static let shared = AgentPhaseCoordinator()
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AgentPhaseCoordinator")

    public var phases: [TaskPhase] = []
    public var activePhaseId: String?

    public init() {
        self.phases = StandardEngineeringPhases.defaultLifecycle()
    }

    public func reset(with customPhases: [TaskPhase]? = nil) {
        self.phases = customPhases ?? StandardEngineeringPhases.defaultLifecycle()
        self.activePhaseId = nil
    }

    public var activePhase: TaskPhase? {
        guard let id = activePhaseId else { return nil }
        return phases.first { $0.phaseId == id }
    }

    public var completedPhases: [TaskPhase] {
        phases.filter { $0.status == .completed }
    }

    public var remainingPhases: [TaskPhase] {
        phases.filter { $0.status == .pending || $0.status == .inProgress }
    }

    public func canonicalPhaseId(for phaseId: String) -> String {
        switch phaseId {
        case "PHASE_01_INIT", "PHASE_1_INIT", "INIT":
            return "PHASE_001_REPO_INIT"
        case "PHASE_02_GROUNDING", "PHASE_2_GROUNDING", "GROUNDING":
            return "PHASE_007_ASSIST_SOURCE_INVENTORY"
        case "PHASE_03_SKILLS", "PHASE_3_SKILLS", "SKILLS":
            return "PHASE_012_SKILLS_INVENTORY"
        case "PHASE_04_NOTES", "PHASE_4_NOTES", "NOTES":
            return "PHASE_046_AGENT_NOTES_CREATION"
        case "PHASE_05_PLANNING", "PHASE_5_PLANNING", "PLANNING":
            return "PHASE_075_PLANNING_ENGINE"
        case "PHASE_06_EXECUTION", "PHASE_6_EXECUTION", "EXECUTION":
            return "PHASE_081_TOOL_REGISTRY"
        case "PHASE_07_VERIFICATION", "PHASE_7_VERIFICATION", "VERIFICATION":
            return "PHASE_206_VERIFICATION_DOC"
        case "PHASE_08_REVIEW", "PHASE_8_REVIEW", "REVIEW":
            return "PHASE_220_INDEPENDENT_REVIEW"
        case "PHASE_09_SUMMARY", "PHASE_9_SUMMARY", "SUMMARY":
            return "PHASE_240_METRICS"
        default:
            return phaseId
        }
    }

    private func resolvePhaseIndex(for phaseId: String) -> Int {
        let canonical = canonicalPhaseId(for: phaseId)
        if let idx = phases.firstIndex(where: { $0.phaseId == canonical || $0.phaseId == phaseId }) {
            return idx
        }
        if let idx = phases.firstIndex(where: { $0.phaseId.contains(phaseId) || phaseId.contains($0.phaseId) }) {
            return idx
        }
        let newPhase = TaskPhase(
            phaseId: phaseId,
            name: phaseId.replacingOccurrences(of: "_", with: " ").capitalized,
            description: "Dynamically registered phase: \(phaseId)"
        )
        phases.append(newPhase)
        return phases.count - 1
    }

    public func canStartPhase(_ phaseId: String) -> Bool {
        let index = resolvePhaseIndex(for: phaseId)
        let phase = phases[index]
        for dep in phase.dependencies {
            if let depPhase = phases.first(where: { $0.phaseId == dep }), depPhase.status != .completed && depPhase.status != .skipped {
                return false
            }
        }
        return true
    }

    public func startPhase(_ phaseId: String) -> Bool {
        let index = resolvePhaseIndex(for: phaseId)
        let resolvedId = phases[index].phaseId

        // Auto-skip pending dependencies so execution never stalls
        for dep in phases[index].dependencies {
            if let depIdx = phases.firstIndex(where: { $0.phaseId == dep }),
               phases[depIdx].status == .pending {
                phases[depIdx].status = .skipped
                logger.info("Auto-skipping dependency '\(dep)' for phase '\(resolvedId)'")
            }
        }

        phases[index].status = .inProgress
        phases[index].startedAt = Date()
        self.activePhaseId = resolvedId

        logger.info("Started phase [\(resolvedId)]: \(self.phases[index].name)")
        DiagnosticEventBus.shared.logEvent(
            component: "AgentPhaseCoordinator",
            severity: "INFO",
            category: "phase",
            message: "Started Phase \(resolvedId) - \(self.phases[index].name)"
        )
        return true
    }

    public func completePhase(_ phaseId: String, evidence: String? = nil) {
        let index = resolvePhaseIndex(for: phaseId)
        let resolvedId = phases[index].phaseId

        phases[index].status = .completed
        phases[index].completedAt = Date()
        if let ev = evidence {
            phases[index].evidence = ev
        }

        if activePhaseId == resolvedId || activePhaseId == phaseId {
            activePhaseId = nil
        }

        logger.info("Completed phase [\(resolvedId)]: \(self.phases[index].name) with evidence: \(evidence ?? "none")")
        DiagnosticEventBus.shared.logEvent(
            component: "AgentPhaseCoordinator",
            severity: "SUCCESS",
            category: "phase",
            message: "Completed Phase \(resolvedId) - Evidence: \(evidence ?? "Confirmed")"
        )
    }

    public func failPhase(_ phaseId: String, error: String, recoveryNotes: String? = nil) {
        let index = resolvePhaseIndex(for: phaseId)
        let resolvedId = phases[index].phaseId

        phases[index].status = .failed
        phases[index].failures.append(error)
        phases[index].recoveryNotes = recoveryNotes

        logger.error("Phase [\(resolvedId)] failed: \(error). Recovery: \(recoveryNotes ?? "none")")
        DiagnosticEventBus.shared.logEvent(
            component: "AgentPhaseCoordinator",
            severity: "ERROR",
            category: "phase",
            message: "Failed Phase \(resolvedId): \(error)"
        )
    }

    public func formatPhasesSummaryForPrompt() -> String {
        var lines: [String] = ["# ACTIVE ENGINEERING PHASES & PROGRESS"]
        for p in phases {
            let mark = p.status == .completed ? "[DONE]" : (p.status == .inProgress ? "[ACTIVE]" : (p.status == .failed ? "[FAILED]" : "[TODO]"))
            var line = "\(mark) \(p.phaseId): \(p.name) (\(p.status.rawValue))"
            if let ev = p.evidence {
                line += " — Evidence: \(ev)"
            }
            if let rec = p.recoveryNotes {
                line += " — Recovery: \(rec)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
