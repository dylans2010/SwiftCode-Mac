//
//  AntigravityLimitsModelsUI.swift
//  SwiftCode
//
//  Dedicated glass-like UI popover displaying official SDK models sorted by thinking level
//  and real Google account allowances.
//  Matches the compact glass styling of AssistCustomModelPickerPopover.
//

import SwiftUI
import AppKit

public struct AntigravityLimitsModelsUI: View {
    public let selectedModelID: String
    public let onSelect: (String) -> Void
    public let onDismiss: () -> Void

    @ObservedObject private var quotaService = AntigravityQuotaService.shared
    @ObservedObject private var modelFetcher = AntigravitySDKModelFetcher.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var showingUsageDetailsPopover: Bool = false
    @State private var selectedThinkingLevel: ThinkingLevel = .high
    @State private var hoveredModelID: String? = nil
    // Discovered SwiftCode Cloud models (server hosts many — never a hardcoded single model).
    @State private var cloudModels: [SCCloudModelInfo] = []

    public enum ThinkingLevel: String, CaseIterable, Identifiable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"

        public var id: String { rawValue }

        public var accentColor: Color {
            switch self {
            case .low: return Color(red: 0.0, green: 0.8, blue: 0.8) // Cyan / Teal
            case .medium: return Color(red: 0.55, green: 0.35, blue: 1.0) // Indigo / Purple
            case .high: return Color(red: 1.0, green: 0.2, blue: 0.5) // Coral / Pink
            }
        }
    }

    /// Dynamic accessor for code referencing `AntigravityLimitsModelsUI.sdkModels`
    public static var sdkModels: [AntigravitySDKModel] {
        AntigravitySDKModelFetcher.shared.models
    }

    public init(
        selectedModelID: String,
        onSelect: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.selectedModelID = selectedModelID
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header with Usage Details, Refresh & Dismiss
            headerView

            // MARK: - Modern Thinking Depth Picker
            thinkingPickerSection

            Divider()

            // MARK: - Models List
            modelsListView
        }
        .frame(width: 320, height: 380)
        .background(.ultraThinMaterial)
        .onAppear {
            quotaService.startPeriodicRefresh()
            syncThinkingLevelWithSelection()
            // Seed from cache, then refresh in the background when stale.
            cloudModels = SCCloudModelDiscovery.shared.models
            Task {
                let fresh = await SCCloudModelDiscovery.shared.refreshIfStale()
                await MainActor.run { cloudModels = fresh }
            }
        }
        .onDisappear {
            quotaService.stopPeriodicRefresh()
        }
        .onChange(of: selectedModelID) { _, _ in
            syncThinkingLevelWithSelection()
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 8) {
            // Usage Details Pill / Button with Live Gauge Color & Percentage
            Button {
                showingUsageDetailsPopover.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.needle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(quotaService.fiveHourGaugeColor)
                    Text("Usage Details")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(quotaService.fiveHourRemainingPercentString)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(quotaService.fiveHourGaugeColor.opacity(0.14), in: Capsule())
                        .foregroundStyle(quotaService.fiveHourGaugeColor)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingUsageDetailsPopover, arrowEdge: .top) {
                usageDetailsPopoverContent
            }
            .help("View Live Usage Details & Limits")

            Spacer()

            // Live Refresh button
            Button {
                Task {
                    quotaService.refreshRealGoogleQuota()
                    await modelFetcher.fetchModels()
                }
            } label: {
                if quotaService.isRefreshingQuota || modelFetcher.isFetching {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Refresh Quota & Models")
            .disabled(quotaService.isRefreshingQuota || modelFetcher.isFetching)

            // Dismiss Button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
    }

    // MARK: - Thinking Depth Picker
    private var thinkingPickerSection: some View {
        HStack(spacing: 2) {
            ForEach(ThinkingLevel.allCases) { level in
                let isSelected = selectedThinkingLevel == level
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectThinkingLevel(level)
                    }
                } label: {
                    Text(level.rawValue)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            isSelected ? Color(NSColor.controlBackgroundColor).opacity(0.8) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? level.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Models List View
    private var modelsListView: some View {
        let models = displayedModels
        return Group {
            if models.isEmpty {
                VStack(spacing: 8) {
                    if modelFetcher.isFetching {
                        ProgressView().scaleEffect(0.8)
                        Text("Loading SDK models...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No models found for selected level.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(models) { model in
                            modelRow(model)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Clean Model Row
    private func modelRow(_ model: AntigravitySDKModel) -> some View {
        let isSelected = selectedModelID == model.id || (selectedModelID.isEmpty && model.id == "gemini-3.8-flash-high")
        let isHovered = hoveredModelID == model.id
        let blurb = cloudBlurb(for: model)

        return Button {
            onSelect(model.id)
            AppSettings.shared.selectedAssistModelID = model.id
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.displayName)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(.primary)
                    if let blurb {
                        Text(blurb)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.06) : (isSelected ? Color.primary.opacity(0.04) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredModelID = hovering ? model.id : nil
        }
    }

    /// Curated blurb for a cloud model row, if the model is a discovered
    /// SwiftCode Cloud model with a known description.
    private func cloudBlurb(for model: AntigravitySDKModel) -> String? {
        guard let endpointName = SCCloudConfiguration.endpointName(forInternalID: model.id) else {
            return nil
        }
        return SCCloudConfiguration.blurb(forEndpointName: endpointName)
    }

    // MARK: - Displayed Models (Filtered by Thinking Level)
    private var displayedModels: [AntigravitySDKModel] {
        let all = modelFetcher.models.isEmpty ? AntigravitySDKModelFetcher.seedModels : modelFetcher.models
        let matching = all.filter { $0.thinkingLevel.lowercased() == selectedThinkingLevel.rawValue.lowercased() }
        var base = matching.isEmpty ? all : matching
        // SwiftCode Cloud Models: pinned to the top whenever the toggle is on,
        // regardless of thinking-level filter or routing strategy. One entry per
        // discovered model, each labeled with its real server-side name
        // (gemma, gpt-oss, qwen, …) — never a single hardcoded model name.
        // Until the first discovery completes, a single honest placeholder
        // entry is shown; it resolves to the first discovered model.
        if settings.useSwiftCodeCloudModel {
            let cloudEntries: [AntigravitySDKModel]
            if cloudModels.isEmpty {
                cloudEntries = [
                    AntigravitySDKModel(
                        id: SCCloudConfiguration.modelIDPrefix,
                        displayName: "SwiftCode Cloud (discovering models…)",
                        thinkingLevel: "Medium",
                        contextWindow: 128_000,
                        category: "SwiftCode"
                    )
                ]
            } else {
                cloudEntries = cloudModels.map { info in
                    AntigravitySDKModel(
                        id: info.internalID,
                        displayName: info.displayName,
                        thinkingLevel: "Medium",
                        contextWindow: info.contextWindow ?? 128_000,
                        category: "SwiftCode"
                    )
                }
            }
            base.removeAll { SCCloudConfiguration.isCloudModelID($0.id) }
            base.insert(contentsOf: cloudEntries, at: 0)
        }
        return base
    }

    // MARK: - Usage Details Popover Content (Live Google Allowance)
    private var usageDetailsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.needle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(quotaService.fiveHourGaugeColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Usage Details")
                        .font(.system(size: 12, weight: .bold))
                    Text("Live Google Allowance")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    quotaService.refreshRealGoogleQuota()
                } label: {
                    if quotaService.isRefreshingQuota {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Check live rate limits via CLI")
                .disabled(quotaService.isRefreshingQuota)
            }

            Divider()

            // MARK: - Section 1: Gemini
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.blue)
                    Text("Gemini")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                }

                compactQuotaCard(
                    title: "Gemini 5-Hour Rate Limit",
                    subtitle: "Resets in \(quotaService.fiveHourResetCountdownString)",
                    percentage: quotaService.fiveHourRemainingPercentage,
                    gaugeColor: quotaService.fiveHourGaugeColor,
                    icon: "arrow.clockwise"
                )

                compactQuotaCard(
                    title: "Gemini Weekly Limit",
                    subtitle: "Resets \(quotaService.weeklyResetString)",
                    percentage: quotaService.weeklyRemainingPercentage,
                    gaugeColor: quotaService.weeklyGaugeColor,
                    icon: "calendar"
                )
            }

            Divider()

            // MARK: - Section 2: Claude & GPT
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.purple)
                    Text("Claude & GPT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                }

                compactQuotaCard(
                    title: "Claude & GPT 5-Hour Limit",
                    subtitle: "Resets in \(quotaService.fiveHourResetCountdownString)",
                    percentage: quotaService.realThreeP5hPercentage,
                    gaugeColor: AntigravityQuotaService.gaugeColor(forPercentage: quotaService.realThreeP5hPercentage),
                    icon: "clock.arrow.circlepath"
                )

                compactQuotaCard(
                    title: "Claude & GPT Weekly Limit",
                    subtitle: "Resets \(quotaService.weeklyResetString)",
                    percentage: quotaService.realThreePWeeklyPercentage,
                    gaugeColor: AntigravityQuotaService.gaugeColor(forPercentage: quotaService.realThreePWeeklyPercentage),
                    icon: "calendar.badge.clock"
                )
            }

            Divider()

            // MARK: - Data source & refresh provenance
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Text(quotaService.quotaDataSourceDescription)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let last = quotaService.lastSuccessfulRefresh {
                    Text("Last refreshed \(last, style: .relative) · auto-refresh every 10 min")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No successful refresh yet · auto-refresh every 10 min")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                if let err = quotaService.lastRefreshError {
                    Text(err)
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                Text("Antigravity account usage: \(quotaService.antigravityAccountUsageStatus)")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .frame(width: 250)
        .background(.ultraThinMaterial)
    }

    private func compactQuotaCard(
        title: String,
        subtitle: String,
        percentage: Double,
        gaugeColor: Color,
        icon: String
    ) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 2.8)
                    .frame(width: 24, height: 24)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(1.0, percentage / 100.0))))
                    .stroke(
                        gaugeColor,
                        style: StrokeStyle(lineWidth: 2.8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 24, height: 24)
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundStyle(gaugeColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(Int(round(percentage)))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(gaugeColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(gaugeColor.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers
    private func selectThinkingLevel(_ level: ThinkingLevel) {
        selectedThinkingLevel = level

        let matching = modelFetcher.models.filter { $0.thinkingLevel.lowercased() == level.rawValue.lowercased() }
        if let preferred = matching.first {
            onSelect(preferred.id)
            AppSettings.shared.selectedAssistModelID = preferred.id
        }
    }

    private func syncThinkingLevelWithSelection() {
        if let currentModel = modelFetcher.models.first(where: { $0.id == selectedModelID }) {
            let lvl = currentModel.thinkingLevel.lowercased()
            if lvl == "high" {
                selectedThinkingLevel = .high
            } else if lvl == "low" || lvl == "minimal" {
                selectedThinkingLevel = .low
            } else {
                selectedThinkingLevel = .medium
            }
        }
    }
}
