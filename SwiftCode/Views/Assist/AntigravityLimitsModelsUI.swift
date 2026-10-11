//
//  AntigravityLimitsModelsUI.swift
//  SwiftCode
//
//  Dedicated UI popover displaying official SDK models and real Google account allowances.
//  Matches the compact styling of AssistCustomModelPickerPopover with a modern, clean thinking slider.
//  No individual model icons, no selection chips, no section header, no bottom footers.
//  Account allowance is presented as "Usage Details" showing live percentages pulled from the Google system.
//  Dynamic gauge colors: 100%-60% green, 59%-21% yellow, 20%-0% red.
//

import SwiftUI
import AppKit

public struct AntigravityLimitsModelsUI: View {
    public let selectedModelID: String
    public let onSelect: (String) -> Void
    public let onDismiss: () -> Void

    @ObservedObject private var quotaService = AntigravityQuotaService.shared
    @ObservedObject private var modelFetcher = AntigravitySDKModelFetcher.shared

    @State private var searchText: String = ""
    @State private var showingUsageDetailsPopover: Bool = false
    @State private var selectedThinkingLevel: ThinkingLevel = .high
    @State private var hoveredModelID: String? = nil

    public enum ThinkingLevel: String, CaseIterable, Identifiable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"

        public var id: String { rawValue }

        public var subtitle: String {
            switch self {
            case .low: return "Low Thinking · Fast generation & rapid edits"
            case .medium: return "Medium Thinking · Balanced multi-step reasoning"
            case .high: return "High Thinking · Deep reasoning & architecture"
            }
        }

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

            // MARK: - Modern, Clean Thinking Depth Slider
            thinkingSliderSection

            // MARK: - Search Bar
            searchBar

            Divider()

            // MARK: - Models List
            modelsListView
        }
        .frame(width: 320, height: 420)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            quotaService.refreshRealGoogleQuota()
            syncThinkingLevelWithSelection()
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

    // MARK: - Modern, Clean Thinking Depth Slider
    private var thinkingSliderSection: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(ThinkingLevel.allCases) { level in
                    let isSelected = selectedThinkingLevel == level
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectThinkingLevel(level)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(level.accentColor)
                                .frame(width: 5, height: 5)
                            Text(level.rawValue)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            isSelected ? Color(NSColor.controlBackgroundColor) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? level.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                        .shadow(color: isSelected ? Color.black.opacity(0.06) : Color.clear, radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            Text(selectedThinkingLevel.subtitle)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search models...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 6)
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
                        Text("No matching models found.")
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

    // MARK: - Model Row (Clean, matches AssistModelPickerRow)
    private func modelRow(_ model: AntigravitySDKModel) -> some View {
        let isSelected = selectedModelID == model.id || (selectedModelID.isEmpty && model.id == "gemini-3.8-flash-high")
        let isHovered = hoveredModelID == model.id

        return Button {
            onSelect(model.id)
            AppSettings.shared.selectedAssistModelID = model.id
        } label: {
            HStack(spacing: 8) {
                // Colored dot by thinking level
                Circle()
                    .fill(model.thinkingColor)
                    .frame(width: 6, height: 6)

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(.primary)

                        // Thinking badge
                        Text(model.thinkingLevel)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(model.thinkingColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(model.thinkingColor)

                        // Context Window
                        Text(formatContextWindow(model.contextWindow))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }

                    Text(model.id)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.05) : (isSelected ? Color.primary.opacity(0.03) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredModelID = hovering ? model.id : nil
        }
    }

    // MARK: - Displayed Models
    private var displayedModels: [AntigravitySDKModel] {
        let all = modelFetcher.models.isEmpty ? AntigravitySDKModelFetcher.seedModels : modelFetcher.models
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            return all.filter {
                $0.displayName.lowercased().contains(query) ||
                $0.id.lowercased().contains(query) ||
                $0.thinkingLevel.lowercased().contains(query)
            }
        }

        // Return models with matching thinking level first, then others
        let matching = all.filter { $0.thinkingLevel.lowercased() == selectedThinkingLevel.rawValue.lowercased() }
        let rest = all.filter { $0.thinkingLevel.lowercased() != selectedThinkingLevel.rawValue.lowercased() }
        return matching + rest
    }

    // MARK: - Usage Details Popover Content (Live Google allowance, percentage only)
    private var usageDetailsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.needle.fill")
                    .font(.headline)
                    .foregroundStyle(quotaService.fiveHourGaugeColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Usage Details")
                        .font(.system(size: 13, weight: .bold))
                    Text("Google Account Allowance")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // 5-Hour Rate Limit Card
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 4.5)
                        .frame(width: 44, height: 44)
                    Circle()
                        .trim(from: 0, to: CGFloat(quotaService.fiveHourRemainingPercentage / 100.0))
                        .stroke(
                            quotaService.fiveHourGaugeColor,
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 44, height: 44)
                    Text(quotaService.fiveHourRemainingPercentString)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(quotaService.fiveHourGaugeColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("5-Hour Rate Limit")
                        .font(.system(size: 11, weight: .bold))

                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8))
                        Text("Resets in \(quotaService.fiveHourResetCountdownString)")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(quotaService.fiveHourGaugeColor)
                }
                Spacer()
            }
            .padding(10)
            .background(quotaService.fiveHourGaugeColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            // Weekly Limit Card
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 4.5)
                        .frame(width: 44, height: 44)
                    Circle()
                        .trim(from: 0, to: CGFloat(quotaService.weeklyRemainingPercentage / 100.0))
                        .stroke(
                            quotaService.weeklyGaugeColor,
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 44, height: 44)
                    Text(quotaService.weeklyRemainingPercentString)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(quotaService.weeklyGaugeColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Weekly Limit")
                        .font(.system(size: 11, weight: .bold))

                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 8))
                        Text("Resets \(quotaService.weeklyResetString)")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(quotaService.weeklyGaugeColor)
                }
                Spacer()
            }
            .padding(10)
            .background(quotaService.weeklyGaugeColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            // Claude & GPT (3P) Models Allowance Card (if available from Google system)
            if quotaService.isUsingRealQuota {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 4.5)
                            .frame(width: 44, height: 44)
                        Circle()
                            .trim(from: 0, to: CGFloat(quotaService.realThreePWeeklyPercentage / 100.0))
                            .stroke(
                                AntigravityQuotaService.gaugeColor(forPercentage: quotaService.realThreePWeeklyPercentage),
                                style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 44, height: 44)
                        Text("\(Int(round(quotaService.realThreePWeeklyPercentage)))%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(AntigravityQuotaService.gaugeColor(forPercentage: quotaService.realThreePWeeklyPercentage))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Claude & GPT Limit")
                            .font(.system(size: 11, weight: .bold))

                        Text("Shared multi-model weekly allowance")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(AntigravityQuotaService.gaugeColor(forPercentage: quotaService.realThreePWeeklyPercentage).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    // MARK: - Helpers
    private func selectThinkingLevel(_ level: ThinkingLevel) {
        selectedThinkingLevel = level

        // Select premier model matching this level
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

    private func formatContextWindow(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return "\(tokens / 1_000_000)M"
        } else {
            return "\(tokens / 1_000)k"
        }
    }
}
