import Foundation
import SwiftUI

/// Logical execution stages for grouping Assist tool activity items.
public enum ToolExecutionStage: String, CaseIterable, Identifiable, Sendable {
    case gitOperations = "Git Operations"
    case buildAndTest = "Build & Verification"
    case workerExecution = "Worker Execution"
    case sourceModifications = "Source Modifications"
    case fileDiscovery = "File Discovery"
    case repositoryInspection = "Repository Inspection"
    case terminalProcesses = "Terminal Processes"
    case recovery = "Recovery & Diagnosis"
    case general = "Operations"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .gitOperations: return "arrow.triangle.branch"
        case .buildAndTest: return "hammer.fill"
        case .workerExecution: return "person.3.sequence.fill"
        case .sourceModifications: return "square.and.pencil"
        case .fileDiscovery: return "magnifyingglass"
        case .repositoryInspection: return "folder.badge.gearshape"
        case .terminalProcesses: return "terminal.fill"
        case .recovery: return "arrow.clockwise.circle.fill"
        case .general: return "wrench.and.screwdriver"
        }
    }

    public static func stage(for toolId: String) -> ToolExecutionStage {
        let lower = toolId.lowercased()
        if lower.contains("git") { return .gitOperations }
        if lower.contains("build") || lower.contains("test") || lower.contains("xcodebuild") { return .buildAndTest }
        if lower.contains("worker") { return .workerExecution }
        if lower.contains("terminal") || lower.contains("process") || lower.contains("bash") || lower.contains("zsh") { return .terminalProcesses }
        if lower.contains("write") || lower.contains("replace") || lower.contains("create") || lower.contains("delete") || lower.contains("edit") || lower.contains("patch") { return .sourceModifications }
        if lower.contains("search") || lower.contains("find") || lower.contains("glob") || lower.contains("list") || lower.contains("tree") { return .fileDiscovery }
        if lower.contains("inspect") || lower.contains("read") || lower.contains("view") || lower.contains("diagnos") || lower.contains("finder") { return .repositoryInspection }
        if lower.contains("recover") || lower.contains("retry") { return .recovery }
        return .general
    }
}

/// A grouped collection of tool activity items belonging to the same stage.
public struct ToolExecutionGroup: Identifiable {
    public let stage: ToolExecutionStage
    public var tools: [ToolActivityItem]

    public var id: String { stage.rawValue }

    public var isExecuting: Bool {
        tools.contains { $0.status == .running || $0.status == .retrying }
    }

    public var hasFailed: Bool {
        tools.contains { $0.status == .failed }
    }

    public var summary: String {
        let completed = tools.filter { $0.status == .completed }.count
        let failed = tools.filter { $0.status == .failed }.count
        let running = tools.filter { $0.status == .running || $0.status == .retrying }.count

        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if completed > 0 { parts.append("\(completed) passed") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: ", ")
    }

    public static func group(tools: [ToolActivityItem]) -> [ToolExecutionGroup] {
        var groupsMap: [ToolExecutionStage: [ToolActivityItem]] = [:]
        var stageOrder: [ToolExecutionStage] = []

        for tool in tools {
            let stage = ToolExecutionStage.stage(for: tool.toolId)
            if groupsMap[stage] == nil {
                stageOrder.append(stage)
                groupsMap[stage] = []
            }
            groupsMap[stage]?.append(tool)
        }

        return stageOrder.compactMap { stage in
            guard let items = groupsMap[stage], !items.isEmpty else { return nil }
            return ToolExecutionGroup(stage: stage, tools: items)
        }
    }
}
