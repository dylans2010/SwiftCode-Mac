import Foundation

/// Centralized event normalizer that converts raw runtime events into deduplicated, retry-aware logical operations.
@MainActor
public final class AssistEventNormalizer {
    public static let shared = AssistEventNormalizer()

    private var activeCallToSemanticKey: [String: String] = [:]
    private var activeCallToOperationId: [String: UUID] = [:]
    private var completedCallIds: Set<String> = []

    private init() {}

    /// Resets all internal tracking structures when starting a new logical task.
    public func resetForNewTask() {
        activeCallToSemanticKey.removeAll()
        activeCallToOperationId.removeAll()
        completedCallIds.removeAll()
    }

    // MARK: - Semantic Operation Key Generator

    public func computeSemanticKey(toolName: String, arguments: [String: Any]) -> String {
        let normalizedTool = toolName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        var keyParts: [String] = [normalizedTool]

        if let path = AssistToolActivityFormatter.extractFilePath(arguments: arguments) {
            keyParts.append("path:\(path.lowercased())")
        } else if let path = arguments["path"] as? String ?? arguments["directory"] as? String {
            keyParts.append("path:\(path.lowercased())")
        }

        if let query = arguments["query"] as? String ?? arguments["pattern"] as? String ?? arguments["searchQuery"] as? String {
            keyParts.append("query:\(query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())")
        }

        if let cmd = arguments["command"] as? String ?? arguments["cmd"] as? String ?? arguments["CommandLine"] as? String {
            keyParts.append("cmd:\(cmd.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())")
        }

        return keyParts.joined(separator: "|")
    }

    // MARK: - Error Message Normalizer

    public func sanitizeErrorMessage(rawError: String, toolName: String) -> String {
        let trimmed = rawError.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "Failed:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty && trimmed.caseInsensitiveCompare("failed") != .orderedSame {
            return trimmed
        }

        let cleanTool = toolName.lowercased()
        if cleanTool.contains("inspect") || cleanTool.contains("dir") {
            return "Directory inspection failed"
        } else if cleanTool.contains("search") || cleanTool.contains("grep") || cleanTool.contains("find") {
            return "Search failed"
        } else if cleanTool.contains("read") {
            return "File read failed"
        } else if cleanTool.contains("write") || cleanTool.contains("edit") || cleanTool.contains("create") {
            return "File modification failed"
        } else if cleanTool.contains("build") {
            return "Build failed"
        } else if cleanTool.contains("test") {
            return "Test execution failed"
        }
        return "Tool execution failed"
    }

    // MARK: - Internal Tool Lookup Helper

    private func findToolIndex(
        callId: String,
        toolName: String,
        semanticKey: String?,
        in tools: [ToolActivityItem],
        requireActive: Bool = false
    ) -> Int? {
        let isActive: (ToolActivityItem) -> Bool = { $0.status == .running || $0.status == .retrying || $0.status == .failed }

        // 1. Direct callId or operationId match
        if !callId.isEmpty {
            if let idx = tools.firstIndex(where: {
                ($0.callId == callId || $0.operationId == callId) && (!requireActive || isActive($0))
            }) {
                return idx
            }
        }

        // 2. Direct UUID match from active mapping or parsed UUID
        let callUUID = callId.isEmpty ? nil : (activeCallToOperationId[callId] ?? UUID(uuidString: callId))
        if let callUUID = callUUID {
            if let idx = tools.firstIndex(where: {
                $0.id == callUUID && (!requireActive || isActive($0))
            }) {
                return idx
            }
        }

        // 3. Semantic key match among active attempts
        if let semKey = semanticKey, !semKey.isEmpty {
            if let idx = tools.firstIndex(where: {
                $0.semanticKey == semKey && isActive($0)
            }) {
                return idx
            }
        }

        // 4. Exact toolId match among active running attempts
        if !toolName.isEmpty && requireActive {
            if let idx = tools.firstIndex(where: {
                $0.toolId == toolName && ($0.status == .running || $0.status == .retrying)
            }) {
                return idx
            }
        }

        return nil
    }

    // MARK: - Tool Event Normalization

    public func normalizeToolStarted(
        callId: String,
        toolName: String,
        arguments: [String: Any],
        in activityGroup: inout AssistActivityGroup
    ) {
        activityGroup.isExecuting = true
        let formatted = AssistToolActivityFormatter.format(toolId: toolName, arguments: arguments)
        let semKey = computeSemanticKey(toolName: toolName, arguments: arguments)
        let callUUID = callId.isEmpty ? UUID() : (activeCallToOperationId[callId] ?? UUID(uuidString: callId) ?? UUID())

        if !callId.isEmpty {
            activeCallToSemanticKey[callId] = semKey
        }

        // Reuse an exact operation ID or merge a semantically identical retry while prior attempt is active/failed.
        // Completed operations must not absorb a later, intentional repeat.
        let existingIdx = findToolIndex(
            callId: callId,
            toolName: toolName,
            semanticKey: semKey,
            in: activityGroup.tools,
            requireActive: true
        ) ?? activityGroup.tools.firstIndex(where: {
            (!callId.isEmpty && ($0.callId == callId || $0.operationId == callId)) ||
            (callUUID != nil && $0.id == callUUID)
        })

        if let existingIdx = existingIdx {
            var existing = activityGroup.tools[existingIdx]
            // A replayed start for an already-completed operation is a duplicate hook/chunk event, not a new attempt.
            guard existing.status != .completed else { return }

            if existing.status == .failed || existing.status == .retrying {
                existing.retryCount += 1
                existing.attemptsCount += 1
                existing.status = .running
                existing.timestamp = Date()
                existing.duration = 0
                if !callId.isEmpty {
                    existing.callId = callId
                    existing.operationId = callId
                }
                existing.purpose = "\(formatted.runningLabel) (Retry \(existing.retryCount + 1))"
            } else {
                existing.status = .running
                existing.purpose = formatted.runningLabel
            }
            existing.displayLabel = formatted.runningLabel
            existing.completedLabel = formatted.completedLabel
            existing.iconName = formatted.iconName
            existing.semanticKey = semKey
            if !callId.isEmpty {
                existing.operationId = callId
            }
            activityGroup.tools[existingIdx] = existing
            if !callId.isEmpty {
                activeCallToOperationId[callId] = existing.id
            }
        } else {
            let argumentsSummary: String
            if let file = AssistToolActivityFormatter.extractFilename(from: arguments) {
                argumentsSummary = file
            } else if let path = AssistToolActivityFormatter.extractFilePath(arguments: arguments) {
                argumentsSummary = path
            } else if let query = AssistToolActivityFormatter.extractSearchQuery(from: arguments) {
                argumentsSummary = query
            } else {
                argumentsSummary = ""
            }

            let newItem = ToolActivityItem(
                id: callUUID,
                callId: callId.isEmpty ? callUUID.uuidString : callId,
                toolId: toolName,
                purpose: formatted.runningLabel,
                argumentsSummary: argumentsSummary,
                streamingOutput: "",
                result: "",
                status: .running,
                progress: nil,
                duration: 0.0,
                timestamp: Date(),
                displayLabel: formatted.runningLabel,
                completedLabel: formatted.completedLabel,
                iconName: formatted.iconName,
                attemptsCount: 1,
                retryCount: 0,
                semanticKey: semKey,
                operationId: callId.isEmpty ? callUUID.uuidString : callId
            )
            activityGroup.tools.append(newItem)
            if !callId.isEmpty {
                activeCallToOperationId[callId] = newItem.id
            }
        }

        // Auxiliary integration logic
        integrateAuxiliaryStarted(toolName: toolName, arguments: arguments, activityGroup: &activityGroup)
    }

    public func normalizeToolProgress(
        callId: String,
        toolName: String = "",
        progressMessage: String,
        progress: Double? = nil,
        in activityGroup: inout AssistActivityGroup
    ) {
        let semKey = activeCallToSemanticKey[callId] ?? (!toolName.isEmpty ? "\(toolName):" : "")
        let targetIdx = findToolIndex(
            callId: callId,
            toolName: toolName,
            semanticKey: semKey,
            in: activityGroup.tools,
            requireActive: true
        ) ?? activityGroup.tools.firstIndex(where: {
            (!semKey.isEmpty && ($0.semanticKey?.hasPrefix(semKey) == true) && $0.status == .running) ||
            (!toolName.isEmpty && $0.toolId == toolName && $0.status == .running)
        })

        if let idx = targetIdx {
            activityGroup.tools[idx].updateProgress(progress: progress, message: progressMessage)
        } else if !callId.isEmpty || !toolName.isEmpty {
            // Buffer initial running item if progress event arrives before start event
            let callUUID = activeCallToOperationId[callId] ?? UUID(uuidString: callId) ?? UUID()
            let item = ToolActivityItem(
                id: callUUID,
                callId: callId.isEmpty ? callUUID.uuidString : callId,
                toolId: toolName.isEmpty ? "tool" : toolName,
                purpose: progressMessage,
                result: progressMessage,
                status: .running,
                progress: progress,
                duration: 0.0,
                timestamp: Date(),
                attemptsCount: 1,
                retryCount: 0,
                semanticKey: semKey,
                operationId: callId.isEmpty ? callUUID.uuidString : callId
            )
            activityGroup.tools.append(item)
            if !callId.isEmpty {
                activeCallToOperationId[callId] = item.id
            }
            activityGroup.isExecuting = true
        }

        integrateAuxiliaryProgress(toolName: toolName, progressMessage: progressMessage, activityGroup: &activityGroup)
    }

    public func normalizeToolOutputChunk(
        callId: String,
        toolName: String = "",
        chunk: String,
        in activityGroup: inout AssistActivityGroup
    ) {
        guard !chunk.isEmpty else { return }
        let semKey = activeCallToSemanticKey[callId] ?? (!toolName.isEmpty ? "\(toolName):" : "")
        let targetIdx = findToolIndex(
            callId: callId,
            toolName: toolName,
            semanticKey: semKey,
            in: activityGroup.tools,
            requireActive: true
        ) ?? activityGroup.tools.firstIndex(where: {
            (!semKey.isEmpty && ($0.semanticKey?.hasPrefix(semKey) == true) && $0.status == .running) ||
            (!toolName.isEmpty && $0.toolId == toolName && $0.status == .running)
        })

        if let idx = targetIdx {
            activityGroup.tools[idx].appendStreamingChunk(chunk)
            activityGroup.isExecuting = true
        } else if !callId.isEmpty || !toolName.isEmpty {
            let callUUID = activeCallToOperationId[callId] ?? UUID(uuidString: callId) ?? UUID()
            let item = ToolActivityItem(
                id: callUUID,
                callId: callId.isEmpty ? callUUID.uuidString : callId,
                toolId: toolName.isEmpty ? "tool" : toolName,
                purpose: "Streaming output…",
                streamingOutput: chunk,
                result: "",
                status: .running,
                progress: nil,
                duration: 0.0,
                timestamp: Date(),
                attemptsCount: 1,
                retryCount: 0,
                semanticKey: semKey,
                operationId: callId.isEmpty ? callUUID.uuidString : callId
            )
            activityGroup.tools.append(item)
            if !callId.isEmpty {
                activeCallToOperationId[callId] = item.id
            }
            activityGroup.isExecuting = true
        }

        integrateAuxiliaryOutputChunk(toolName: toolName, chunk: chunk, activityGroup: &activityGroup)
    }

    public func normalizeToolCompleted(
        callId: String,
        toolName: String,
        output: String?,
        arguments: [String: Any] = [:],
        in activityGroup: inout AssistActivityGroup
    ) {
        let formatted = AssistToolActivityFormatter.format(toolId: toolName, arguments: arguments)
        let semKey = activeCallToSemanticKey[callId] ?? computeSemanticKey(toolName: toolName, arguments: arguments)

        let targetIdx = findToolIndex(
            callId: callId,
            toolName: toolName,
            semanticKey: semKey,
            in: activityGroup.tools,
            requireActive: false
        )

        if let idx = targetIdx {
            var item = activityGroup.tools[idx]
            if item.status != .completed {
                item.duration = max(0.1, Date().timeIntervalSince(item.timestamp))
            }
            item.status = .completed
            if let output = output, !output.isEmpty {
                item.result = output
            } else if item.result.isEmpty && !item.streamingOutput.isEmpty {
                item.result = item.streamingOutput
            }
            item.purpose = formatted.completedLabel
            item.completedLabel = formatted.completedLabel
            item.progress = 1.0
            activityGroup.tools[idx] = item
            if !callId.isEmpty {
                completedCallIds.insert(callId)
            }
        } else {
            // Check if exact completed item already exists to avoid transport replay duplication
            let isDuplicate = activityGroup.tools.contains(where: {
                (!callId.isEmpty && ($0.callId == callId || $0.operationId == callId)) ||
                ($0.toolId == toolName && $0.status == .completed && $0.semanticKey == semKey)
            })
            if !isDuplicate {
                let callUUID = callId.isEmpty ? UUID() : (activeCallToOperationId[callId] ?? UUID(uuidString: callId) ?? UUID())
                let newItem = ToolActivityItem(
                    id: callUUID,
                    callId: callId.isEmpty ? callUUID.uuidString : callId,
                    toolId: toolName,
                    purpose: formatted.completedLabel,
                    result: output ?? "",
                    status: .completed,
                    progress: 1.0,
                    duration: 0.1,
                    timestamp: Date(),
                    displayLabel: formatted.runningLabel,
                    completedLabel: formatted.completedLabel,
                    iconName: formatted.iconName,
                    attemptsCount: 1,
                    retryCount: 0,
                    semanticKey: semKey,
                    operationId: callId.isEmpty ? callUUID.uuidString : callId
                )
                activityGroup.tools.append(newItem)
                if !callId.isEmpty {
                    completedCallIds.insert(callId)
                }
            }
        }

        integrateAuxiliaryCompleted(toolName: toolName, output: output, activityGroup: &activityGroup)
        activityGroup.refreshExecutingState()
    }

    public func normalizeToolFailed(
        callId: String,
        toolName: String,
        error: String,
        arguments: [String: Any] = [:],
        in activityGroup: inout AssistActivityGroup
    ) {
        let cleanError = sanitizeErrorMessage(rawError: error, toolName: toolName)
        let formatted = AssistToolActivityFormatter.format(toolId: toolName, arguments: arguments)
        let semKey = activeCallToSemanticKey[callId] ?? computeSemanticKey(toolName: toolName, arguments: arguments)

        let targetIdx = findToolIndex(
            callId: callId,
            toolName: toolName,
            semanticKey: semKey,
            in: activityGroup.tools,
            requireActive: false
        )

        if let idx = targetIdx {
            var item = activityGroup.tools[idx]
            item.status = .failed
            item.result = cleanError
            item.duration = max(0.1, Date().timeIntervalSince(item.timestamp))
            item.purpose = "\(formatted.failedLabel) — \(cleanError)"
            activityGroup.tools[idx] = item
        } else {
            let callUUID = callId.isEmpty ? UUID() : (activeCallToOperationId[callId] ?? UUID(uuidString: callId) ?? UUID())
            let newItem = ToolActivityItem(
                id: callUUID,
                callId: callId.isEmpty ? callUUID.uuidString : callId,
                toolId: toolName,
                purpose: "\(formatted.failedLabel) — \(cleanError)",
                result: cleanError,
                status: .failed,
                duration: 0.1,
                timestamp: Date(),
                displayLabel: formatted.runningLabel,
                completedLabel: formatted.completedLabel,
                iconName: formatted.iconName,
                attemptsCount: 1,
                retryCount: 0,
                semanticKey: semKey,
                operationId: callId.isEmpty ? callUUID.uuidString : callId
            )
            activityGroup.tools.append(newItem)
        }

        integrateAuxiliaryFailed(toolName: toolName, error: cleanError, activityGroup: &activityGroup)
        activityGroup.refreshExecutingState()
    }

    public func normalizeToolCancelled(
        callId: String,
        toolName: String = "",
        reason: String = "Operation cancelled",
        in activityGroup: inout AssistActivityGroup
    ) {
        let targetIdx = findToolIndex(
            callId: callId,
            toolName: toolName,
            semanticKey: activeCallToSemanticKey[callId],
            in: activityGroup.tools,
            requireActive: false
        )

        if let idx = targetIdx {
            activityGroup.tools[idx].markCancelled(reason: reason)
        } else if callId.isEmpty {
            for idx in activityGroup.tools.indices where activityGroup.tools[idx].isRunning {
                activityGroup.tools[idx].markCancelled(reason: reason)
            }
        }
        activityGroup.refreshExecutingState()
    }

    public func normalizeToolTimedOut(
        callId: String,
        toolName: String = "",
        duration: TimeInterval? = nil,
        in activityGroup: inout AssistActivityGroup
    ) {
        let targetIdx = findToolIndex(
            callId: callId,
            toolName: toolName,
            semanticKey: activeCallToSemanticKey[callId],
            in: activityGroup.tools,
            requireActive: false
        )

        if let idx = targetIdx {
            activityGroup.tools[idx].markTimedOut(duration: duration)
        } else if callId.isEmpty {
            for idx in activityGroup.tools.indices where activityGroup.tools[idx].isRunning {
                activityGroup.tools[idx].markTimedOut(duration: duration)
            }
        }
        activityGroup.refreshExecutingState()
    }

    public func finalizeAllRunningOperations(
        status: ActivityStatus = .cancelled,
        reason: String? = nil,
        in activityGroup: inout AssistActivityGroup
    ) {
        activityGroup.finalizeAllRunningOperations(status: status, reason: reason)
    }

    // MARK: - Worker Normalization

    public func normalizeWorkerStarted(
        workerId: String,
        name: String,
        args: String,
        in activityGroup: inout AssistActivityGroup
    ) {
        activityGroup.isExecuting = true
        let cleanName = name.replacingOccurrences(of: "start_subagent", with: "")
            .replacingOccurrences(of: "Worker:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleanName.isEmpty ? "Worker" : "Worker · \(cleanName)"

        if let existingIdx = activityGroup.workers.firstIndex(where: { $0.workerId == workerId || $0.name == name }) {
            activityGroup.workers[existingIdx].status = .running
            activityGroup.workers[existingIdx].taskDescription = args
        } else {
            let item = WorkerActivityItem(
                workerId: workerId,
                name: name,
                role: "Subagent",
                scope: "Workspace",
                taskDescription: args,
                status: .running,
                progress: 0.0,
                userFacingTitle: title
            )
            activityGroup.workers.append(item)
        }
    }

    public func normalizeWorkerProgress(
        workerId: String,
        progress: Double? = nil,
        statusMessage: String? = nil,
        in activityGroup: inout AssistActivityGroup
    ) {
        if let idx = activityGroup.workers.firstIndex(where: { $0.workerId == workerId || $0.status == .running }) {
            if let p = progress {
                activityGroup.workers[idx].progress = min(max(p, 0.0), 1.0)
            }
            if let msg = statusMessage, !msg.isEmpty {
                activityGroup.workers[idx].taskDescription = msg
            }
        }
    }

    public func normalizeWorkerCompleted(
        workerId: String,
        result: String,
        in activityGroup: inout AssistActivityGroup
    ) {
        if let idx = activityGroup.workers.firstIndex(where: { $0.workerId == workerId || $0.status == .running }) {
            activityGroup.workers[idx].status = .completed
            activityGroup.workers[idx].progress = 1.0
        }
        activityGroup.refreshExecutingState()
    }

    public func normalizeWorkerFailed(
        workerId: String,
        error: String,
        in activityGroup: inout AssistActivityGroup
    ) {
        if let idx = activityGroup.workers.firstIndex(where: { $0.workerId == workerId || $0.status == .running }) {
            activityGroup.workers[idx].status = .failed
            let cleanErr = sanitizeErrorMessage(rawError: error, toolName: "worker")
            activityGroup.workers[idx].taskDescription = cleanErr
        }
        activityGroup.refreshExecutingState()
    }

    // MARK: - Private Auxiliary Handlers

    private func integrateAuxiliaryStarted(toolName: String, arguments: [String: Any], activityGroup: inout AssistActivityGroup) {
        if let path = AssistToolActivityFormatter.extractFilePath(arguments: arguments) {
            if let op = AssistToolActivityFormatter.determineFileOperation(toolId: toolName) {
                if !activityGroup.files.contains(where: { $0.filePath == path }) {
                    activityGroup.files.append(FileActivityItem(filePath: path, operation: op))
                }
            }
        }

        let isBuild = toolName == "project_build" || toolName == "build_project" || toolName == "build"
        if isBuild {
            if let bIdx = activityGroup.builds.firstIndex(where: { $0.status == .running || $0.status == .failed }) {
                activityGroup.builds[bIdx].status = .running
                activityGroup.builds[bIdx].attemptsCount += 1
            } else if !activityGroup.builds.contains(where: { $0.status == .running }) {
                activityGroup.builds.append(BuildActivityItem(scheme: "SwiftCode", status: .running))
            }
        }

        let isTest = toolName == "run_tests" || toolName == "test_runner" || toolName == "test"
        if isTest {
            if let tIdx = activityGroup.tests.firstIndex(where: { $0.status == .running || $0.status == .failed }) {
                activityGroup.tests[tIdx].status = .running
                activityGroup.tests[tIdx].attemptsCount += 1
            } else if !activityGroup.tests.contains(where: { $0.status == .running }) {
                activityGroup.tests.append(TestActivityItem(suiteName: "SwiftCodeTests", status: .running))
            }
        }

        let isTerminal = toolName == "use_terminal" || toolName == "task_runner" || toolName == "run_command"
        if isTerminal {
            let rawCmd = arguments["command"] as? String ?? arguments["CommandLine"] as? String ?? arguments["cmd"] as? String ?? ""
            if !rawCmd.isEmpty {
                if let termIdx = activityGroup.terminalCommands.firstIndex(where: { $0.command == rawCmd }) {
                    activityGroup.terminalCommands[termIdx].status = .running
                    activityGroup.terminalCommands[termIdx].attemptsCount += 1
                } else {
                    activityGroup.terminalCommands.append(TerminalActivityItem(
                        command: rawCmd,
                        workingDirectory: ".",
                        output: "",
                        exitCode: 0,
                        status: .running,
                        timestamp: Date()
                    ))
                }
            }
        }
    }

    private func integrateAuxiliaryProgress(toolName: String, progressMessage: String, activityGroup: inout AssistActivityGroup) {
        let isTerminal = toolName == "use_terminal" || toolName == "task_runner" || toolName == "run_command"
        if isTerminal {
            for cIdx in activityGroup.terminalCommands.indices where activityGroup.terminalCommands[cIdx].status == .running {
                activityGroup.terminalCommands[cIdx].output = progressMessage
            }
        }
    }

    private func integrateAuxiliaryOutputChunk(toolName: String, chunk: String, activityGroup: inout AssistActivityGroup) {
        let isTerminal = toolName == "use_terminal" || toolName == "task_runner" || toolName == "run_command"
        if isTerminal {
            for cIdx in activityGroup.terminalCommands.indices where activityGroup.terminalCommands[cIdx].status == .running {
                activityGroup.terminalCommands[cIdx].output.append(chunk)
            }
        }
    }

    private func integrateAuxiliaryCompleted(toolName: String, output: String?, activityGroup: inout AssistActivityGroup) {
        let isBuild = toolName == "project_build" || toolName == "build_project" || toolName == "build"
        if isBuild {
            for bIdx in activityGroup.builds.indices where activityGroup.builds[bIdx].status == .running {
                activityGroup.builds[bIdx].status = .completed
                activityGroup.builds[bIdx].duration = max(0.1, Date().timeIntervalSince(activityGroup.builds[bIdx].timestamp))
            }
        }

        let isTest = toolName == "run_tests" || toolName == "test_runner" || toolName == "test"
        if isTest {
            for tIdx in activityGroup.tests.indices where activityGroup.tests[tIdx].status == .running {
                activityGroup.tests[tIdx].status = .completed
                activityGroup.tests[tIdx].passedCount = max(1, activityGroup.tests[tIdx].passedCount)
                activityGroup.tests[tIdx].duration = max(0.1, Date().timeIntervalSince(activityGroup.tests[tIdx].timestamp))
            }
        }

        let isTerminal = toolName == "use_terminal" || toolName == "task_runner" || toolName == "run_command"
        if isTerminal {
            for cIdx in activityGroup.terminalCommands.indices where activityGroup.terminalCommands[cIdx].status == .running {
                activityGroup.terminalCommands[cIdx].status = .completed
                if let output = output, !output.isEmpty {
                    activityGroup.terminalCommands[cIdx].output = output
                }
            }
        }
    }

    private func integrateAuxiliaryFailed(toolName: String, error: String, activityGroup: inout AssistActivityGroup) {
        let isBuild = toolName == "project_build" || toolName == "build_project" || toolName == "build"
        if isBuild {
            for bIdx in activityGroup.builds.indices where activityGroup.builds[bIdx].status == .running {
                activityGroup.builds[bIdx].status = .failed
                activityGroup.builds[bIdx].errorCount = 1
                activityGroup.builds[bIdx].duration = max(0.1, Date().timeIntervalSince(activityGroup.builds[bIdx].timestamp))
            }
        }

        let isTest = toolName == "run_tests" || toolName == "test_runner" || toolName == "test"
        if isTest {
            for tIdx in activityGroup.tests.indices where activityGroup.tests[tIdx].status == .running {
                activityGroup.tests[tIdx].status = .failed
                activityGroup.tests[tIdx].failedCount = 1
                activityGroup.tests[tIdx].duration = max(0.1, Date().timeIntervalSince(activityGroup.tests[tIdx].timestamp))
            }
        }

        let isTerminal = toolName == "use_terminal" || toolName == "task_runner" || toolName == "run_command"
        if isTerminal {
            for cIdx in activityGroup.terminalCommands.indices where activityGroup.terminalCommands[cIdx].status == .running {
                activityGroup.terminalCommands[cIdx].status = .failed
                activityGroup.terminalCommands[cIdx].output = error
            }
        }
    }
}
