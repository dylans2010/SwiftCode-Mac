//
//  AssistInfoView.swift
//  SwiftCode
//
//  Compact, translucent information banner displayed at the top of a user chat message
//  when a slash (/) or at (@) command was executed. Displays what the user did along with
//  skills, rules, referenced resources, and task feedback.
//

import SwiftUI

public struct AssistInfoView: View {
    public let envelope: AssistTaskEnvelope?
    public let messageText: String

    @State private var isExpanded: Bool = false

    public init(envelope: AssistTaskEnvelope?, messageText: String) {
        self.envelope = envelope
        self.messageText = messageText
    }

    /// Derives the executed command or at-resource from envelope or text inspection.
    private var detectedCommand: (type: String, name: String, argument: String)? {
        if let env = envelope, let slash = env.slashCommand, !slash.isEmpty {
            return ("Slash Command", slash.hasPrefix("/") ? slash : "/\(slash)", env.commandArgument ?? "")
        }

        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            let tokens = trimmed.components(separatedBy: .whitespaces)
            let cmd = tokens.first ?? ""
            let arg = tokens.dropFirst().joined(separator: " ")
            return ("Slash Command", cmd, arg)
        } else if trimmed.hasPrefix("@") {
            let tokens = trimmed.components(separatedBy: .whitespaces)
            let res = tokens.first ?? ""
            let arg = tokens.dropFirst().joined(separator: " ")
            return ("Resource Mention", res, arg)
        }

        if let env = envelope, let res = env.executedResources, !res.isEmpty {
            return ("Resource", res.joined(separator: ", "), "")
        }

        return nil
    }

    public var body: some View {
        if let cmd = detectedCommand {
            VStack(alignment: .leading, spacing: 6) {
                // Header Banner Row
                HStack(spacing: 7) {
                    Image(systemName: cmd.name.hasPrefix("/") ? "terminal" : "at")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.75))

                    Text(cmd.name)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.primary)

                    if !cmd.argument.isEmpty {
                        Text(cmd.argument)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Expand / Collapse Details Button
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(isExpanded ? "Hide Details" : "Details")
                                .font(.system(size: 9.5, weight: .medium))
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // Expanded Info Breakdown (Skills, Rules, Resources, Feedback)
                if isExpanded {
                    VStack(alignment: .leading, spacing: 5) {
                        Divider()
                            .opacity(0.3)

                        if let env = envelope {
                            if !env.explicitSkills.isEmpty {
                                HStack(alignment: .top, spacing: 4) {
                                    Text("Skills:")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 65, alignment: .leading)

                                    Text(env.explicitSkills.map(\.name).joined(separator: ", "))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.primary)
                                }
                            }

                            if let rule = env.taskRule, !rule.isEmpty {
                                HStack(alignment: .top, spacing: 4) {
                                    Text("Rule:")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 65, alignment: .leading)

                                    Text(rule)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.primary)
                                }
                            }

                            if let res = env.executedResources, !res.isEmpty {
                                HStack(alignment: .top, spacing: 4) {
                                    Text("Resources:")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 65, alignment: .leading)

                                    Text(res.joined(separator: ", "))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.primary)
                                }
                            }

                            if let meta = env.metadata, !meta.isEmpty {
                                HStack(alignment: .top, spacing: 4) {
                                    Text("Context:")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 65, alignment: .leading)

                                    Text(meta.map { "\($0.key)=\($0.value)" }.joined(separator: "; "))
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text("Command executed in session. Assist is evaluating guidelines and constraints.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
            )
            .padding(.bottom, 2)
        }
    }
}
