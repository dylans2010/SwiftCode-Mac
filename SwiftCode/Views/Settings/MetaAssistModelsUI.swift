//
//  MetaAssistModelsUI.swift
//  SwiftCode
//
//  Models selection and reasoning effort control card for "Assist with Meta" (Muse SDK).
//

import SwiftUI

public struct MetaAssistModelsUI: View {
    @ObservedObject private var settings = AppSettings.shared

    @State private var models: [MetaModelItem] = []
    @State private var cloudModels: [SCCloudModelInfo] = []
    @State private var otherModels: [AssistAvailableModel] = []
    @State private var isLoadingModels: Bool = false
    @State private var loadError: String? = nil

    private let reasoningTiers: [String] = [
        "none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"
    ]

    public init() {}

    public var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(
                                colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 28, height: 28)
                        Image(systemName: "apple.intelligence")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.blue)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("Assist with Meta Models")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Models")
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                        Text("Available models from the Meta catalog & bridged providers")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        let totalCount = models.count + (settings.otherModelsWithMetaSDK || settings.swiftCodeCloudWithMetaSDK ? cloudModels.count + otherModels.count : 0)
                        if totalCount > 0 {
                            Text("\(totalCount) Models")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            Task { await loadModels() }
                        } label: {
                            if isLoadingModels {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Refresh Models")
                        .disabled(isLoadingModels)
                    }
                }

                Divider()

                // Other Models with Meta SDK Bridge Card
                otherModelsBridgeCard

                Divider()

                // 1. Models List
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Available Models")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        if settings.otherModelsWithMetaSDK || settings.swiftCodeCloudWithMetaSDK {
                            Text("Muse + Bridged")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(.purple)
                        } else {
                            Text("Native Muse")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if isLoadingModels && models.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Fetching Models…")
                                .scaleEffect(0.7)
                                .font(.caption2)
                                .padding(.vertical, 12)
                            Spacer()
                        }
                    } else if let error = loadError, models.isEmpty {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .padding(.vertical, 2)
                    } else {
                        // Scrollable list so all models fit neatly
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: 4) {
                                // Section A: Native Meta Muse Models
                                ForEach(models) { model in
                                    modelRow(model)
                                }

                                // Section B: Divider & All Other Models (when toggle is ON)
                                if settings.otherModelsWithMetaSDK || settings.swiftCodeCloudWithMetaSDK {
                                    HStack(spacing: 8) {
                                        Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.triangle.branch")
                                                .font(.system(size: 8.5))
                                            Text("Other & Bridged Models")
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                        .foregroundStyle(.purple)
                                        Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                                    }
                                    .padding(.vertical, 3)

                                    // 1. SwiftCode Cloud Models
                                    ForEach(cloudModels, id: \.endpointName) { cloud in
                                        otherModelRow(
                                            id: cloud.internalID,
                                            displayName: cloud.displayName,
                                            provider: "SwiftCode Cloud",
                                            description: cloud.blurb ?? "SwiftCode Cloud hosted model",
                                            contextLimit: cloud.contextWindow ?? 128_000,
                                            badge: "Cloud",
                                            isCloud: true
                                        )
                                    }

                                    // 2. Saved Third-Party API Models
                                    let candidateOther = otherModels.filter {
                                        $0.source != .custom && $0.source != .local && !SCCloudConfiguration.isCloudModelID($0.id)
                                    }
                                    ForEach(candidateOther) { model in
                                        otherModelRow(
                                            id: model.modelIdentifier,
                                            displayName: model.displayName,
                                            provider: model.providerName,
                                            description: model.statusDescription ?? "\(model.providerName) bridged model",
                                            contextLimit: model.contextWindow,
                                            badge: "API",
                                            isCloud: false
                                        )
                                    }

                                    // 3. Custom Model Setups
                                    let customEndpoints = CustomEndpointManager.shared.endpoints
                                    ForEach(customEndpoints) { endpoint in
                                        let eligible = AssistModelEligibilityPolicy.filterEligibleModelIDs(endpoint.models, onlyUseFreeModels: settings.onlyUseFreeModels)
                                        ForEach(eligible, id: \.self) { modelID in
                                            otherModelRow(
                                                id: modelID,
                                                displayName: "\(endpoint.name): \(modelID)",
                                                provider: endpoint.name,
                                                description: "Custom endpoint model (\(endpoint.isLocal ? "Local" : "Remote"))",
                                                contextLimit: 128_000,
                                                badge: "Custom",
                                                isCloud: false
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.trailing, 2)
                        }
                        .frame(maxHeight: 280)
                    }
                }

                Divider()

                // 2. Thinking Models / Reasoning Effort Section
                reasoningEffortCard
            }
            .padding(10)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
        .task {
            await loadModels()
        }
    }

    // MARK: - Native Muse Model Card Row (Compact)

    @ViewBuilder
    private func modelRow(_ model: MetaModelItem) -> some View {
        let isSelected: Bool = {
            if (settings.otherModelsWithMetaSDK || settings.swiftCodeCloudWithMetaSDK) && !settings.metaSelectedOtherModelID.isEmpty {
                return false
            }
            return settings.metaAssistModelID == model.modelId
                || (settings.metaAssistModelID.isEmpty && model.isDefault)
        }()

        Button {
            settings.metaAssistModelID = model.modelId
            settings.selectedAssistModelID = model.modelId
            settings.metaSelectedOtherModelID = ""
            Task {
                try? await MetaAssistProvider.shared.switchModel(modelId: model.modelId)
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.5))
                    .font(.system(size: 11, weight: .medium))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(model.displayLabel)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)

                        Text("Meta")
                            .font(.system(size: 8.5, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)

                        if model.isDefault {
                            Text("Default")
                                .font(.system(size: 8.5, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }

                        if isSelected {
                            Text("Active")
                                .font(.system(size: 8.5, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.15), in: Capsule())
                                .foregroundStyle(.green)
                        }
                    }

                    if let desc = model.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatContextLimit(model.contextLimit))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("context")
                        .font(.system(size: 7.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Other / Bridged Model Card Row (Compact)

    @ViewBuilder
    private func otherModelRow(
        id: String,
        displayName: String,
        provider: String,
        description: String?,
        contextLimit: Int?,
        badge: String? = nil,
        isCloud: Bool = false
    ) -> some View {
        let isSelected = settings.metaSelectedOtherModelID == id
            || (settings.metaSelectedOtherModelID.isEmpty && settings.selectedAssistModelID == id)

        Button {
            settings.metaSelectedOtherModelID = id
            settings.metaSelectedOtherModelProvider = provider
            settings.selectedAssistModelID = id
            settings.metaAssistModelID = id
            if isCloud {
                settings.useSwiftCodeCloudModel = true
                SCCloudDeviceFingerprint.ensureFingerprint()
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? (isCloud ? Color.blue : Color.purple) : Color.secondary.opacity(0.5))
                    .font(.system(size: 11, weight: .medium))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(displayName)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(provider)
                            .font(.system(size: 8.5, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(isCloud ? Color.blue.opacity(0.12) : Color.purple.opacity(0.12), in: Capsule())
                            .foregroundStyle(isCloud ? .blue : .purple)

                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 8.5, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                                .foregroundStyle(.orange)
                        }

                        if isSelected {
                            Text("Active")
                                .font(.system(size: 8.5, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.15), in: Capsule())
                                .foregroundStyle(.green)
                        }
                    }

                    if let desc = description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let contextLimit = contextLimit, contextLimit > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(formatContextLimit(contextLimit))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("context")
                            .font(.system(size: 7.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? (isCloud ? Color.blue.opacity(0.08) : Color.purple.opacity(0.08)) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? (isCloud ? Color.blue.opacity(0.4) : Color.purple.opacity(0.4)) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Other Models with Meta SDK Bridge Card (Compact)

    @ViewBuilder
    private var otherModelsBridgeCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Row 1: Other Models with Meta SDK Toggle
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple)
                    Text("Other Models with Meta SDK")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                Spacer()
                Toggle("", isOn: $settings.otherModelsWithMetaSDK)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            // Row 2: SwiftCode Cloud Models with Meta SDK Toggle
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("SwiftCode Cloud Models with Meta SDK")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                Spacer()
                let remaining = SCCloudRateLimiter.shared.remainingToday
                Text("\(remaining)/\(SCCloudConfiguration.dailyRequestLimit) left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(remaining > 0 ? Color.secondary : Color.orange)
                Toggle("", isOn: $settings.swiftCodeCloudWithMetaSDK)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            Text("Run Assist with Meta via third-party APIs (OpenAI, Claude, Gemini, OpenRouter), Custom endpoints, or SwiftCode's Cloud Models.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            if settings.otherModelsWithMetaSDK || settings.swiftCodeCloudWithMetaSDK {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()

                    // Fallback toggle
                    Toggle(isOn: $settings.useOtherModelsWhenRateLimited) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Use Other Models when Rate Limited")
                                .font(.system(size: 10, weight: .medium))
                            Text("Auto-failover if Meta models hit rate limits (429) or token quotas.")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    // Free-only toggle
                    Toggle(isOn: $settings.onlyUseFreeModels) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Only Use Free Models")
                                .font(.system(size: 10, weight: .medium))
                            Text("Filters models to show only free models where supported.")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    Divider()

                    // Active Bridged Model Picker
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Active Bridged Model")
                            .font(.system(size: 10, weight: .medium))

                        let availableModels = otherModels.isEmpty ? MuseOtherModelsBridge.shared.availableOtherModels() : otherModels
                        let activeModel = MuseOtherModelsBridge.shared.resolveActiveModel()

                        Menu {
                            // Section 1: SwiftCode Cloud Models
                            let candidateClouds = cloudModels.isEmpty ? SCCloudModelDiscovery.shared.models : cloudModels
                            if !candidateClouds.isEmpty {
                                Section("SwiftCode Cloud Models") {
                                    ForEach(candidateClouds, id: \.endpointName) { model in
                                        Button {
                                            settings.metaSelectedOtherModelID = model.internalID
                                            settings.metaSelectedOtherModelProvider = SCCloudConfiguration.providerName
                                            settings.selectedAssistModelID = model.internalID
                                            settings.useSwiftCodeCloudModel = true
                                            SCCloudDeviceFingerprint.ensureFingerprint()
                                        } label: {
                                            HStack {
                                                Text("SwiftCode Cloud: \(model.displayName)")
                                                if settings.metaSelectedOtherModelID == model.internalID {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Section 2: Saved API Providers & Models
                            Section("Saved API Providers & Models") {
                                ForEach(availableModels.filter { $0.source != .custom && $0.source != .local && !SCCloudConfiguration.isCloudModelID($0.id) }) { model in
                                    Button {
                                        settings.metaSelectedOtherModelID = model.modelIdentifier
                                        settings.metaSelectedOtherModelProvider = model.providerName
                                        settings.selectedAssistModelID = model.modelIdentifier
                                    } label: {
                                        HStack {
                                            Text(model.displayName)
                                            if settings.metaSelectedOtherModelID == model.modelIdentifier {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }

                            // Section 3: Custom Model Setups
                            let customEndpoints = CustomEndpointManager.shared.endpoints
                            if !customEndpoints.isEmpty {
                                Section("Custom Model Setups") {
                                    ForEach(customEndpoints) { endpoint in
                                        let eligibleModels = AssistModelEligibilityPolicy.filterEligibleModelIDs(endpoint.models, onlyUseFreeModels: settings.onlyUseFreeModels)
                                        ForEach(eligibleModels, id: \.self) { modelID in
                                            Button {
                                                settings.metaSelectedOtherModelID = modelID
                                                settings.metaSelectedOtherModelProvider = endpoint.name
                                                settings.selectedAssistModelID = modelID
                                            } label: {
                                                HStack {
                                                    Text("\(endpoint.name): \(modelID)")
                                                    if settings.metaSelectedOtherModelID == modelID {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.purple)
                                    .font(.system(size: 10))
                                Text(activeModel.displayName)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Text(activeModel.provider)
                                    .font(.system(size: 8.5, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.purple.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.purple)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
                .padding(7)
                .background(Color.purple.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.purple.opacity(0.15), lineWidth: 1))
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Reasoning Effort / Thinking Models Card (Compact)

    @ViewBuilder
    private var reasoningEffortCard: some View {
        let currentEffort = settings.metaReasoningEffort.isEmpty ? "high" : settings.metaReasoningEffort
        let currentIndex = reasoningTiers.firstIndex(of: currentEffort) ?? 4

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple)
                    Text("Model Thinking Effort")
                        .font(.system(size: 11, weight: .semibold))
                }

                Spacer()

                Text(effortDisplayName(currentEffort))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(effortBadgeColor(currentEffort).opacity(0.15), in: Capsule())
                    .foregroundStyle(effortBadgeColor(currentEffort))
            }

            VStack(alignment: .leading, spacing: 3) {
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
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("High (default)")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Ultra (max depth)")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                }
            }

            Text(effortDescription(currentEffort))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(Color.purple.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
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

        cloudModels = SCCloudModelDiscovery.shared.models
        if cloudModels.isEmpty {
            cloudModels = await SCCloudModelDiscovery.shared.refreshIfStale()
        }
        if cloudModels.isEmpty {
            cloudModels = [
                SCCloudModelInfo(endpointName: "qwen2.5-coder:7b"),
                SCCloudModelInfo(endpointName: "qwen2.5-coder:1.5b"),
                SCCloudModelInfo(endpointName: "gemini"),
                SCCloudModelInfo(endpointName: "swiftcode-cloud")
            ]
        }

        otherModels = MuseOtherModelsBridge.shared.availableOtherModels()
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

