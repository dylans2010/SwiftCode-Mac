//
//  MetaAssistModelsUI.swift
//  SwiftCode
//
//  Models and reasoning effort control card for "Assist with Meta" (Muse SDK).
//

import SwiftUI

public struct MetaAssistModelsUI: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var metaAuth = MetaAccountAuthService.shared

    @State private var models: [MetaModelItem] = []
    @State private var isLoadingModels: Bool = false
    @State private var loadError: String? = nil

    private let reasoningTiers: [String] = [
        "none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"
    ]

    public init() {}

    public var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(
                                colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 32, height: 32)
                        Image(systemName: "cpu.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.blue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Assist with Meta Models")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Muse SDK")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                        Text("Active models and real-time reasoning controls via Meta CLI")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task { await loadModels() }
                    } label: {
                        if isLoadingModels {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Refresh models from Meta CLI")
                    .disabled(isLoadingModels)
                }

                // Authentication Status Bar
                HStack(spacing: 6) {
                    if let email = metaAuth.userEmail, !email.isEmpty {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                        Text("Meta Account: \(email)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 12))
                        Text("Meta Account: Authenticated via CLI")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("1M Context Window")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

                Divider()

                // 1. Meta Models Selection Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Available Models")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("\(models.count) models")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    if isLoadingModels && models.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Fetching models catalog…")
                                .scaleEffect(0.8)
                                .font(.caption2)
                                .padding(.vertical, 12)
                            Spacer()
                        }
                    } else if let error = loadError, models.isEmpty {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(models) { model in
                                modelRow(model)
                            }
                        }
                    }
                }

                Divider()

                // 2. Thinking Slider / Reasoning Effort Section
                reasoningEffortCard
            }
            .padding(14)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
        .task {
            await loadModels()
        }
    }

    // MARK: - Model Card Row

    @ViewBuilder
    private func modelRow(_ model: MetaModelItem) -> some View {
        let isSelected = settings.metaAssistModelID == model.modelId
            || (settings.metaAssistModelID.isEmpty && model.isDefault)

        Button {
            settings.metaAssistModelID = model.modelId
            if settings.selectedAssistModelID != model.modelId {
                settings.selectedAssistModelID = model.modelId
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.5))
                    .font(.system(size: 13, weight: .medium))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.displayLabel)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)

                        if model.isDefault {
                            Text("Default")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }

                        if isSelected {
                            Text("Active")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.green.opacity(0.15), in: Capsule())
                                .foregroundStyle(.green)
                        }
                    }

                    if let desc = model.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatContextLimit(model.contextLimit))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("context")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reasoning Effort Slider View

    @ViewBuilder
    private var reasoningEffortCard: some View {
        let currentEffort = settings.metaReasoningEffort.isEmpty ? "high" : settings.metaReasoningEffort
        let currentIndex = reasoningTiers.firstIndex(of: currentEffort) ?? 4

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.purple)
                    Text("Model Thinking Effort")
                        .font(.system(size: 12, weight: .semibold))
                }

                Spacer()

                Text(effortDisplayName(currentEffort))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(effortBadgeColor(currentEffort).opacity(0.15), in: Capsule())
                    .foregroundStyle(effortBadgeColor(currentEffort))
            }

            VStack(alignment: .leading, spacing: 4) {
                Slider(
                    value: Binding<Double>(
                        get: { Double(currentIndex) },
                        set: { newIdx in
                            let clamped = max(0, min(reasoningTiers.count - 1, Int(newIdx.rounded())))
                            settings.metaReasoningEffort = reasoningTiers[clamped]
                        }
                    ),
                    in: 0...Double(reasoningTiers.count - 1),
                    step: 1
                )
                .tint(.purple)

                HStack {
                    Text("Fastest (none)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("High (default)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Ultra (max depth)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            Text(effortDescription(currentEffort))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(10)
        .background(Color.purple.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func loadModels() async {
        isLoadingModels = true
        loadError = nil
        do {
            let fetched = try await MetaAssistProvider.shared.fetchModels()
            models = fetched
        } catch {
            models = MetaAssistProvider.shared.fallbackModels()
        }
        isLoadingModels = false
    }

    private func formatContextLimit(_ limit: Int) -> String {
        if limit >= 1_000_000 {
            return String(format: "%.1fM", Double(limit) / 1_000_000.0)
        } else if limit >= 1_000 {
            return "\(limit / 1000)k"
        } else {
            return "\(limit)"
        }
    }

    private func effortDisplayName(_ effort: String) -> String {
        switch effort.lowercased() {
        case "none": return "None (0)"
        case "minimal": return "Minimal"
        case "low": return "Low"
        case "medium": return "Medium"
        case "high": return "High (Default)"
        case "xhigh": return "Extra High"
        case "max": return "Maximum"
        case "ultra": return "Ultra Depth"
        default: return effort.capitalized
        }
    }

    private func effortBadgeColor(_ effort: String) -> Color {
        switch effort.lowercased() {
        case "none", "minimal": return .gray
        case "low": return .teal
        case "medium": return .blue
        case "high": return .purple
        case "xhigh", "max": return .orange
        case "ultra": return .pink
        default: return .purple
        }
    }

    private func effortDescription(_ effort: String) -> String {
        switch effort.lowercased() {
        case "none":
            return "No reasoning steps. Emits immediate responses without internal thinking steps."
        case "minimal":
            return "Minimal reasoning tokens for rapid responses and simple single-line syntax questions."
        case "low":
            return "Lightweight chain-of-thought analysis for routine coding tasks and quick questions."
        case "medium":
            return "Balanced reasoning for everyday multi-file edits, refactoring, and code review."
        case "high":
            return "Deep step-by-step reasoning for diagnosing complex bugs and systematic refactoring (Default)."
        case "xhigh":
            return "Extended reasoning for intricate architectural changes, concurrency, and tricky edge cases."
        case "max":
            return "Maximum reasoning effort for the hardest logic puzzles and deep algorithmic problems."
        case "ultra":
            return "Exhaustive reasoning depth with complete verification passes across complex codebases."
        default:
            return "Adjusts the depth of reasoning steps performed by the Meta model before emitting code."
        }
    }
}
