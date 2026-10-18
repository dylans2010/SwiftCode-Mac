//
//  MuseSDKToolCall.swift
//  SwiftCode
//
//  Dedicated UI displayed when calling Muse tools.
//  Uses clean blue styling, badge "Muse Tool", with no all-caps headings and no "SDK" references.
//

import SwiftUI
import AppKit

public struct MuseSDKToolCall: View {
    public let tool: ToolActivityItem
    public let fileDiffs: [FileActivityItem]

    @State private var isOpen: Bool = false
    @State private var isResultExpanded: Bool = false
    @State private var isCopied: Bool = false

    public init(tool: ToolActivityItem, fileDiffs: [FileActivityItem] = []) {
        self.tool = tool
        self.fileDiffs = fileDiffs
    }

    private var displayTitle: String {
        if let label = tool.displayLabel, !label.isEmpty, !isRawIdentifier(label) {
            return label
        }
        return humanReadableTitle(for: tool.toolId)
    }

    private func isRawIdentifier(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("file_") ||
               lower.contains("code_") ||
               lower.contains("dir_") ||
               lower.contains("use_terminal") ||
               lower.contains("plan-askuser") ||
               lower.contains("type:") ||
               lower.contains("properties") ||
               lower.contains("schema")
    }

    private func humanReadableTitle(for rawId: String) -> String {
        let norm = rawId.lowercased().replacingOccurrences(of: "-", with: "_")
        switch norm {
        case "file_read", "read_file", "view_file":
            return "Reading File Content (Muse Tool)"
        case "file_write", "write_file":
            return "Writing File Content (Muse Tool)"
        case "code_replace", "replace_in_file":
            return "Applying Code Edit (Muse Tool)"
        case "use_terminal", "run_command", "terminal":
            return "Executing Shell Command (Muse Tool)"
        default:
            let cleaned = rawId
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
            return cleaned.isEmpty ? "Muse Tool Action" : "\(cleaned) (Muse Tool)"
        }
    }

    private var cleanParameters: [(key: String, value: String)] {
        var params: [(key: String, value: String)] = []
        if let semKey = tool.semanticKey, !semKey.isEmpty {
            let parts = semKey.components(separatedBy: "|")
            for part in parts.dropFirst() {
                let kv = part.components(separatedBy: ":")
                if kv.count >= 2 {
                    let k = kv[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let v = kv.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !k.isEmpty && !v.isEmpty {
                        params.append((key: k.capitalized, value: v))
                    }
                }
            }
        }
        return params
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Summary Row Button
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isOpen.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // Status Icon
                    statusIcon

                    // Muse SF Symbol in Blue
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.blue)
                        .frame(width: 16, height: 16)

                    // Human-Readable Title
                    Text(displayTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    // Distinct Muse Tool Badge in Blue (No SDK, no uppercase)
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8, weight: .bold))
                        Text("Muse Tool")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12), in: Capsule())

                    Spacer(minLength: 4)

                    // Duration
                    if tool.duration > 0 {
                        Text(String(format: "%.1fs", tool.duration))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
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

            // Expanded Details
            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .opacity(0.35)

                    if !tool.purpose.isEmpty {
                        Text(MuseNativeToolCard.hidesToolSchemaOnUI(rawText: tool.purpose, toolId: tool.toolId))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .padding(.horizontal, 4)
                    }

                    if !cleanParameters.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Parameters")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.blue)

                            ForEach(cleanParameters, id: \.key) { param in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("\(param.key):")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .leading)

                                    Text(param.value)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.primary.opacity(0.9))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 1)
                            }
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }

                    if !tool.result.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Outcome")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.blue)

                                Spacer()

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(tool.result, forType: .string)
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

                            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                                Text(tool.result)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .frame(maxHeight: isResultExpanded ? .infinity : 200)
                            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.25), lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch tool.status {
        case .running, .retrying:
            ProgressView()
                .scaleEffect(0.35)
                .frame(width: 14, height: 14)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.blue)
                .frame(width: 14, height: 14)
        case .failed, .cancelled:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.red)
                .frame(width: 14, height: 14)
        case .pending, .skipped:
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
                .frame(width: 14, height: 14)
        }
    }
}
