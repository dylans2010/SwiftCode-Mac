//
//  MetaAssistToolsUI.swift
//  SwiftCode
//
//  Small card-based Thinking UI for "Assist with Meta" / Muse turns.
//  Displays thought process, live reasoning metrics, and plans what tools
//  to use when thinking as an interactive planned-tools roadmap card.
//

import SwiftUI
import AppKit

// MARK: - Legacy MetaAssistToolsUI Adapter

/// Backward-compatible wrapper that directs tool execution rendering to
/// `MuseCallsNativeToolsUI` (now the default tool execution UI).
public struct MetaAssistToolsUI: View {
    public let activityGroup: AssistActivityGroup

    public init(activityGroup: AssistActivityGroup) {
        self.activityGroup = activityGroup
    }

    public var body: some View {
        MuseCallsNativeToolsUI(activityGroup: activityGroup)
    }
}

// MARK: - Small Card-Based Thinking UI

/// Small card-based Thinking UI that presents the model's reasoning process,
/// streaming state, duration, and extracts a planned-tools roadmap based on thinking content.
public struct MetaAssistThinkingUI: View {
    public let thinkingContent: String
    public let duration: TimeInterval?
    public let isStreaming: Bool

    @State private var isOpen: Bool = false
    @State private var isCopied: Bool = false
    @State private var isExpanded: Bool = false

    public init(
        thinkingContent: String,
        duration: TimeInterval? = nil,
        isStreaming: Bool = false
    ) {
        self.thinkingContent = thinkingContent
        self.duration = duration
        self.isStreaming = isStreaming
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Small Card Container
            VStack(alignment: .leading, spacing: 0) {
                // Header Bar (Collapsible Button)
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isOpen.toggle()
                    }
                } label: {
                    HStack(spacing: 7) {
                        // Thinking Icon
                        if isStreaming {
                            ProgressView()
                                .scaleEffect(0.4)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.purple)
                                .frame(width: 14, height: 14)
                        }

                        // Title
                        Text(headerTitle)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(isStreaming ? Color.accentColor : Color.primary.opacity(0.85))

                        if let d = duration, d > 0, !isStreaming {
                            Text(String(format: "· %.1fs", d))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        // Planned Tools Count Badge
                        let planned = plannedTools
                        if !planned.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 9))
                                Text("\(planned.count) planned")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.purple)
                        }

                        // Chevron
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Expanded Card Content
                if isOpen {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                            .opacity(0.35)

                        // 1. Planned Tools Roadmap (What tools to use when thinking)
                        let planned = plannedTools
                        if !planned.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "map.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                    Text("PLANNED TOOL ROADMAP")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(Array(planned.enumerated()), id: \.offset) { index, item in
                                            HStack(spacing: 4) {
                                                Image(systemName: item.icon)
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(Color.accentColor)

                                                Text(item.name)
                                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                                    .foregroundStyle(Color.primary.opacity(0.9))
                                            }
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))

                                            if index < planned.count - 1 {
                                                Image(systemName: "arrow.right")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .padding(8)
                            .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        }

                        // 2. Action Buttons (Expand & Copy)
                        HStack {
                            Text("REASONING STREAM")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.tertiary)

                            Spacer()

                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 8))
                                    Text(isExpanded ? "Collapse" : "Expand")
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(thinkingContent, forType: .string)
                                isCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                    isCopied = false
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 8))
                                    Text(isCopied ? "Copied" : "Copy")
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .foregroundStyle(isCopied ? Color.green : Color.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        }

                        // 3. Scrollable Thinking Content
                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            Text(thinkingContent)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineSpacing(3.5)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: isExpanded ? .infinity : 220)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .liquidGlass(style: .standard, cornerRadius: 8, tint: .purple)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerTitle: String {
        if isStreaming {
            return "Thinking & Planning Tools…"
        }
        return "Thought Process & Tool Plan"
    }

    // MARK: - Plan What Tools to Use When Thinking

    public struct PlannedToolInfo: Identifiable {
        public let id = UUID()
        public let name: String
        public let icon: String
        public let toolId: String
    }

    private var plannedTools: [PlannedToolInfo] {
        var items: [PlannedToolInfo] = []
        let lower = thinkingContent.lowercased()

        // Analyze reasoning text for tool intents
        if lower.contains("worker") || lower.contains("subagent") || lower.contains("parallel") || lower.contains("decompose") {
            items.append(PlannedToolInfo(name: "Coordinate Workers", icon: "person.3.sequence.fill", toolId: "use_workers"))
        }

        if lower.contains("read") || lower.contains("inspect") || lower.contains("examine") || lower.contains("view file") || lower.contains("check file") {
            items.append(PlannedToolInfo(name: "Inspect Files", icon: "doc.text.magnifyingglass", toolId: "file_read"))
        }

        if lower.contains("search") || lower.contains("grep") || lower.contains("find") || lower.contains("scan") {
            items.append(PlannedToolInfo(name: "Search Codebase", icon: "magnifyingglass", toolId: "search_text"))
        }

        if lower.contains("replace") || lower.contains("edit") || lower.contains("modify") || lower.contains("refactor") || lower.contains("fix") {
            items.append(PlannedToolInfo(name: "Code Edit", icon: "text.badge.checkmark", toolId: "code_replace"))
        }

        if lower.contains("create file") || lower.contains("write file") || lower.contains("new file") {
            items.append(PlannedToolInfo(name: "Write File", icon: "doc.badge.plus", toolId: "file_write"))
        }

        if lower.contains("build") || lower.contains("compile") || lower.contains("xcodebuild") {
            items.append(PlannedToolInfo(name: "Build Project", icon: "hammer.fill", toolId: "project_build"))
        }

        if lower.contains("test") || lower.contains("verify") || lower.contains("audit") {
            items.append(PlannedToolInfo(name: "Run Tests / Verify", icon: "play.circle.fill", toolId: "project_test"))
        }

        if lower.contains("terminal") || lower.contains("shell") || lower.contains("script") || lower.contains("bash") || lower.contains("command") {
            items.append(PlannedToolInfo(name: "Terminal Command", icon: "terminal.fill", toolId: "use_terminal"))
        }

        if lower.contains("ask user") || lower.contains("clarif") || lower.contains("decision") {
            items.append(PlannedToolInfo(name: "Decision Prompt", icon: "questionmark.bubble.fill", toolId: "plan-AskUser"))
        }

        if lower.contains("report") || lower.contains("complete") || lower.contains("finish") || lower.contains("summary") {
            items.append(PlannedToolInfo(name: "Task Report", icon: "bubble.left.and.exclamationmark.bubble.right.fill", toolId: "report_to_user"))
        }

        return items
    }
}
