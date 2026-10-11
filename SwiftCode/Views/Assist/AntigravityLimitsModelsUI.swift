//
//  AntigravityLimitsModelsUI.swift
//  SwiftCode
//
//  Modern, dedicated UI card displaying official SDK models and user account allowances.
//  Models are fetched dynamically using Process from the SDK runtime.
//  Never displays "Antigravity" in any user-facing UI labels.
//  Features a dynamic gauge color system (100%-60% green, 59%-21% yellow, 20%-0% red)
//  and a super modern colorful glowing orb slider for thinking depth (Low, Medium, High).
//

import SwiftUI
import AppKit

public struct AntigravityLimitsModelsUI: View {
    public let selectedModelID: String
    public let onSelect: (String) -> Void
    public let onDismiss: () -> Void

    @ObservedObject private var quotaService = AntigravityQuotaService.shared
    @ObservedObject private var googleAuth = GoogleAccountAuthService.shared
    @ObservedObject private var modelFetcher = AntigravitySDKModelFetcher.shared

    @State private var showingLimitsPopover: Bool = false
    @State private var showingPlanSelector: Bool = false
    @State private var selectedThinkingLevel: ThinkingLevel = .medium
    @State private var activeFilterTab: ModelFilterTab = .all
    @State private var orbDragOffset: CGFloat? = nil
    @State private var isExecutingProcess: Bool = false
    @State private var liveFetchedModels: [AntigravitySDKModel] = []

    public enum ThinkingLevel: String, CaseIterable, Identifiable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"

        public var id: String { rawValue }

        public var index: Int {
            switch self {
            case .low: return 0
            case .medium: return 1
            case .high: return 2
            }
        }

        public var subtitle: String {
            switch self {
            case .low: return "Fast generation & rapid code edits"
            case .medium: return "Balanced multi-step reasoning"
            case .high: return "Deep architecture & AST refactoring"
            }
        }

        public var orbColors: [Color] {
            switch self {
            case .low:
                return [Color(red: 0.05, green: 0.95, blue: 0.85), Color(red: 0.0, green: 0.6, blue: 0.95)]
            case .medium:
                return [Color(red: 0.55, green: 0.35, blue: 1.0), Color(red: 0.85, green: 0.25, blue: 0.95)]
            case .high:
                return [Color(red: 1.0, green: 0.2, blue: 0.55), Color(red: 1.0, green: 0.6, blue: 0.2)]
            }
        }

        public var glowColor: Color {
            switch self {
            case .low: return Color(red: 0.0, green: 0.85, blue: 0.85)
            case .medium: return Color(red: 0.65, green: 0.35, blue: 1.0)
            case .high: return Color(red: 1.0, green: 0.25, blue: 0.5)
            }
        }
    }

    public enum ModelFilterTab: String, CaseIterable, Identifiable {
        case all = "All"
        case high = "High"
        case medium = "Medium"
        case low = "Low"

        public var id: String { rawValue }
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
            // MARK: - Header with User Profile, Plan Tier & Allowance
            headerView

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    // MARK: - Super Modern Custom Thinking Orbs Slider
                    thinkingOrbsSliderSection

                    // MARK: - Models Section Header & Filter Tabs
                    modelsFilterHeader

                    // MARK: - Dynamic SDK Models List (Showing off all fetched models)
                    modelsListSection
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            Divider()

            // MARK: - Footer
            footerView
        }
        .frame(width: 420, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if liveFetchedModels.isEmpty && !AntigravitySDKModelFetcher.shared.models.isEmpty {
                liveFetchedModels = AntigravitySDKModelFetcher.shared.models
            }
            syncThinkingLevelWithSelection()
            loadModelsViaProcess()
        }
        .onChange(of: selectedModelID) { _, _ in
            syncThinkingLevelWithSelection()
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 10) {
            // App / SDK Icon Orb
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: quotaService.planTier.gradientColors.map { $0.opacity(0.25) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: quotaService.planTier.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 32, height: 32)
                Image(systemName: "cpu.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: quotaService.planTier.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // User Profile & Status
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Official SDK Models")
                        .font(.system(size: 13, weight: .bold))

                    // Subscriber Plan Tier Pill (Clickable to switch / inspect)
                    Button {
                        showingPlanSelector.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: quotaService.planTier.iconName)
                                .font(.system(size: 8, weight: .bold))
                            Text(quotaService.planTier.rawValue.uppercased())
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            LinearGradient(
                                colors: quotaService.planTier.gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                        .foregroundStyle(.white)
                        .shadow(color: quotaService.planTier.gradientColors.first?.opacity(0.3) ?? .clear, radius: 3)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingPlanSelector, arrowEdge: .top) {
                        planTierPickerPopover
                    }
                    .help("Plan: \(quotaService.planTier.displayName)")
                }

                if let email = googleAuth.userEmail, !email.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text(email)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 5, height: 5)
                        Text("Google Account Active")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // "See Limits" & Percentage Allowance Button with Dynamic Gauge Color
            Button {
                showingLimitsPopover.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.needle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(quotaService.fiveHourGaugeColor)
                    Text("\(quotaService.fiveHourRemainingPercentString) left")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(quotaService.fiveHourGaugeColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(quotaService.fiveHourGaugeColor.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(quotaService.fiveHourGaugeColor.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingLimitsPopover, arrowEdge: .top) {
                limitsPopoverContent
            }
            .help("View Account Allowance & Quotas")

            // Dismiss Button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.025))
    }

    // MARK: - Thinking Orbs Slider Section
    private var thinkingOrbsSliderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Slider Header
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(selectedThinkingLevel.glowColor)
                    Text("Thinking Process")
                        .font(.system(size: 11, weight: .bold))
                }

                Spacer()

                // Active Thinking Level Badge
                Text(selectedThinkingLevel.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(
                        LinearGradient(
                            colors: selectedThinkingLevel.orbColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .foregroundStyle(.white)
                    .shadow(color: selectedThinkingLevel.glowColor.opacity(0.4), radius: 4)
            }

            // Custom Glowing Orbs Slider Control
            GeometryReader { geometry in
                let trackWidth = geometry.size.width
                let orbRadius: CGFloat = 13
                let usableWidth = max(10, trackWidth - orbRadius * 2)

                ZStack(alignment: .leading) {
                    // Track Background
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 10)

                    // Track Gradient Mesh Fill
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    ThinkingLevel.low.orbColors.first ?? .cyan,
                                    ThinkingLevel.medium.orbColors.first ?? .purple,
                                    ThinkingLevel.high.orbColors.first ?? .pink
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 4)
                        .padding(.horizontal, orbRadius)

                    // Milestone Orb Station Rings (Low, Medium, High)
                    ForEach(ThinkingLevel.allCases) { level in
                        let stationOffset = orbRadius + CGFloat(level.index) * (usableWidth / 2.0)
                        let isCurrent = selectedThinkingLevel == level

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                                selectThinkingLevel(level)
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(level.glowColor.opacity(isCurrent ? 0.35 : 0.12))
                                    .frame(width: 18, height: 18)
                                Circle()
                                    .fill(Color(NSColor.windowBackgroundColor))
                                    .frame(width: 12, height: 12)
                                Circle()
                                    .fill(level.glowColor)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .buttonStyle(.plain)
                        .position(x: stationOffset, y: geometry.size.height / 2)
                    }

                    // Interactive Draggable Glowing Orb Thumb
                    let currentTargetX = orbRadius + CGFloat(selectedThinkingLevel.index) * (usableWidth / 2.0)
                    let thumbX = orbDragOffset ?? currentTargetX

                    ZStack {
                        // Outer Radiant Glow
                        Circle()
                            .fill(selectedThinkingLevel.glowColor.opacity(0.45))
                            .frame(width: 32, height: 32)
                            .blur(radius: 6)

                        // 3D Glass Orb Sphere
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.9),
                                        selectedThinkingLevel.orbColors.first ?? .purple,
                                        selectedThinkingLevel.orbColors.last ?? .indigo
                                    ]),
                                    center: .topLeading,
                                    startRadius: 2,
                                    endRadius: 18
                                )
                            )
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)

                        // Specular Highlight
                        Circle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 4, height: 4)
                            .offset(x: -4, y: -4)
                    }
                    .position(x: thumbX, y: geometry.size.height / 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let clampedX = min(max(orbRadius, value.location.x), trackWidth - orbRadius)
                                orbDragOffset = clampedX
                            }
                            .onEnded { value in
                                let clampedX = min(max(orbRadius, value.location.x), trackWidth - orbRadius)
                                let progress = (clampedX - orbRadius) / usableWidth
                                let targetLevel: ThinkingLevel
                                if progress < 0.28 {
                                    targetLevel = .low
                                } else if progress > 0.72 {
                                    targetLevel = .high
                                } else {
                                    targetLevel = .medium
                                }

                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    orbDragOffset = nil
                                    selectThinkingLevel(targetLevel)
                                }
                            }
                    )
                }
            }
            .frame(height: 36)

            // Stations Labels
            HStack {
                stationLabel(level: .low, label: "Low")
                Spacer()
                stationLabel(level: .medium, label: "Medium")
                Spacer()
                stationLabel(level: .high, label: "High")
            }
            .padding(.horizontal, 4)

            // Thinking Explanation Pill
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.max.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(selectedThinkingLevel.glowColor)
                Text(selectedThinkingLevel.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                let matchingCount = activeModelsList.filter { $0.thinkingLevel.lowercased() == selectedThinkingLevel.rawValue.lowercased() }.count
                Text("\(matchingCount) SDK models")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(selectedThinkingLevel.glowColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selectedThinkingLevel.glowColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selectedThinkingLevel.glowColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func stationLabel(level: ThinkingLevel, label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                selectThinkingLevel(level)
            }
        } label: {
            HStack(spacing: 3) {
                Circle()
                    .fill(level.glowColor)
                    .frame(width: 4, height: 4)
                Text(label)
                    .font(.system(size: 10, weight: selectedThinkingLevel == level ? .bold : .medium))
                    .foregroundStyle(selectedThinkingLevel == level ? level.glowColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Models Filter Header
    private var modelsFilterHeader: some View {
        HStack {
            Text("OFFICIAL SDK MODELS (\(activeModelsList.count))")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)

            Spacer()

            // Filter Tabs: All, High, Medium, Low
            HStack(spacing: 3) {
                ForEach(ModelFilterTab.allCases) { tab in
                    let isSelected = activeFilterTab == tab
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            activeFilterTab = tab
                            if tab == .high { selectedThinkingLevel = .high }
                            else if tab == .medium { selectedThinkingLevel = .medium }
                            else if tab == .low { selectedThinkingLevel = .low }
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(isSelected ? Color.blue.opacity(0.18) : Color.primary.opacity(0.03), in: Capsule())
                            .foregroundStyle(isSelected ? Color.blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var activeModelsList: [AntigravitySDKModel] {
        if !liveFetchedModels.isEmpty {
            return liveFetchedModels
        }
        return modelFetcher.models
    }

    private var filteredModels: [AntigravitySDKModel] {
        let base = activeModelsList
        switch activeFilterTab {
        case .all:
            return base
        case .high:
            return base.filter { $0.thinkingLevel.lowercased() == "high" }
        case .medium:
            return base.filter { $0.thinkingLevel.lowercased() == "medium" }
        case .low:
            return base.filter { $0.thinkingLevel.lowercased() == "low" || $0.thinkingLevel.lowercased() == "minimal" }
        }
    }

    // MARK: - Dynamic SDK Models List
    private var modelsListSection: some View {
        VStack(spacing: 6) {
            if isExecutingProcess && activeModelsList.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Fetching available models from SDK...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if filteredModels.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("No models discovered for \(activeFilterTab.rawValue) filter.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("Show All Models") {
                        activeFilterTab = .all
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(filteredModels) { model in
                    let isSelected = selectedModelID == model.id || (selectedModelID.isEmpty && model.id == "gemini-3.8-flash-high")
                    let isMatchingThinking = model.thinkingLevel.lowercased() == selectedThinkingLevel.rawValue.lowercased()

                    Button {
                        onSelect(model.id)
                        AppSettings.shared.selectedAssistModelID = model.id
                    } label: {
                        HStack(spacing: 9) {
                            // Model Orb Icon
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(model.thinkingColor.opacity(isSelected ? 0.22 : 0.08))
                                    .frame(width: 32, height: 32)
                                Image(systemName: model.iconName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(model.thinkingColor)
                            }

                            // Model Information
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(model.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    if isMatchingThinking {
                                        Circle()
                                            .fill(selectedThinkingLevel.glowColor)
                                            .frame(width: 4, height: 4)
                                    }
                                }

                                HStack(spacing: 6) {
                                    // Thinking badge
                                    HStack(spacing: 2.5) {
                                        Image(systemName: "sparkle")
                                            .font(.system(size: 7))
                                        Text(model.thinkingLevel)
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(model.thinkingColor.opacity(0.12), in: Capsule())
                                    .foregroundStyle(model.thinkingColor)

                                    // Category / Provider
                                    Text(model.category)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.secondary)

                                    // Context Window
                                    Text(formatContextWindow(model.contextWindow))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            // Selected Indicator
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.green)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? model.thinkingColor.opacity(0.1) : Color.primary.opacity(0.02))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isSelected ? model.thinkingColor.opacity(0.4) : Color.clear, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Footer
    private var footerView: some View {
        HStack(spacing: 6) {
            Image(systemName: "shield.checkmark.fill")
                .font(.system(size: 10))
                .foregroundStyle(.green)
            Text("Zero API Keys · Powered by Account Allowance")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer()

            // Live Refresh button using Process
            Button {
                loadModelsViaProcess()
            } label: {
                HStack(spacing: 3) {
                    if isExecutingProcess {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                    }
                    Text("Refresh")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isExecutingProcess)
            .help("Refetch models live via Process from SDK CLI")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Plan Tier Picker Popover
    private var planTierPickerPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(.orange)
                Text("Select Plan Tier")
                    .font(.system(size: 12, weight: .bold))
            }

            Text("Matches your subscription allowance and sets rate limit headroom:")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(AntigravityPlanTier.allCases, id: \.rawValue) { tier in
                let isCurrent = quotaService.planTier == tier
                Button {
                    quotaService.setPlanTier(tier)
                    showingPlanSelector = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tier.iconName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(tier.gradientColors.first ?? .blue)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(tier.displayName)
                                    .font(.system(size: 11, weight: .bold))
                                if isCurrent {
                                    Text("Active")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.2), in: Capsule())
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(tier.summary)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isCurrent {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(8)
                    .background(isCurrent ? Color.blue.opacity(0.08) : Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 290)
    }

    // MARK: - Limits Popover Content
    private var limitsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with Dynamic Gauge Color
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.headline)
                    .foregroundStyle(quotaService.fiveHourGaugeColor)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("Account Allowance")
                            .font(.system(size: 13, weight: .bold))
                        Text(quotaService.planTier.rawValue)
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                LinearGradient(
                                    colors: quotaService.planTier.gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule()
                            )
                            .foregroundStyle(.white)
                    }
                    Text("Strictly utilizing user profile allowance · Zero API keys")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // 5-Hour Rate Limit Ring Card with Dynamic Gauge Color
            HStack(spacing: 12) {
                // Radial Meter with Dynamic Gauge Color (Green / Yellow / Red)
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 5)
                        .frame(width: 48, height: 48)
                    Circle()
                        .trim(from: 0, to: CGFloat(quotaService.fiveHourRemainingPercentage / 100.0))
                        .stroke(
                            quotaService.fiveHourGaugeColor,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 48, height: 48)
                    Text(quotaService.fiveHourRemainingPercentString)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(quotaService.fiveHourGaugeColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("5-Hour Rate Limit")
                            .font(.system(size: 11, weight: .bold))
                        Spacer()
                        Text("\(quotaService.fiveHourRemaining) left")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(quotaService.fiveHourGaugeColor)
                    }

                    Text("\(quotaService.fiveHourUsed) of \(quotaService.fiveHourLimit) used")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8))
                        Text("Resets in \(quotaService.fiveHourResetCountdownString)")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(quotaService.fiveHourGaugeColor)
                }
            }
            .padding(10)
            .background(quotaService.fiveHourGaugeColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            // Weekly Limit Ring Card with Dynamic Gauge Color
            HStack(spacing: 12) {
                // Radial Meter with Dynamic Gauge Color (Green / Yellow / Red)
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 5)
                        .frame(width: 48, height: 48)
                    Circle()
                        .trim(from: 0, to: CGFloat(quotaService.weeklyRemainingPercentage / 100.0))
                        .stroke(
                            quotaService.weeklyGaugeColor,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 48, height: 48)
                    Text(quotaService.weeklyRemainingPercentString)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(quotaService.weeklyGaugeColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Weekly Allowance")
                            .font(.system(size: 11, weight: .bold))
                        Spacer()
                        Text("\(quotaService.weeklyRemaining) left")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(quotaService.weeklyGaugeColor)
                    }

                    Text("\(quotaService.weeklyUsed) of \(quotaService.weeklyLimit) used")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 8))
                        Text("Resets \(quotaService.weeklyResetString)")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(quotaService.weeklyGaugeColor)
                }
            }
            .padding(10)
            .background(quotaService.weeklyGaugeColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            // Footer info
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Allowances renew automatically according to your \(quotaService.planTier.displayName).")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Process Execution (Dynamic SDK Models Fetching)
    private func loadModelsViaProcess() {
        guard !isExecutingProcess else { return }
        isExecutingProcess = true

        DispatchQueue.global(qos: .userInitiated).async {
            let agyBinaryCandidates = [
                "/Users/dylan/.gemini/bin/agy",
                "/usr/local/bin/agy",
                "/opt/homebrew/bin/agy",
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/bin/agy").path
            ]

            var foundOutput: String? = nil

            for binaryPath in agyBinaryCandidates {
                if FileManager.default.isExecutableFile(atPath: binaryPath) {
                    let process = Process()
                    let pipe = Pipe()

                    process.executableURL = URL(fileURLWithPath: binaryPath)
                    process.arguments = ["models"]
                    process.standardOutput = pipe
                    process.standardError = Pipe()

                    var env = ProcessInfo.processInfo.environment
                    env["PAGER"] = "cat"
                    env["NO_COLOR"] = "1"
                    env["TERM"] = "dumb"
                    process.environment = env

                    do {
                        try process.run()
                        process.waitUntilExit()

                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                            foundOutput = output
                            break
                        }
                    } catch {
                        continue
                    }
                }
            }

            let parsed: [AntigravitySDKModel]
            if let output = foundOutput {
                parsed = AntigravitySDKModelFetcher.shared.parseAgyModelsOutput(output)
            } else {
                parsed = []
            }

            DispatchQueue.main.async {
                self.isExecutingProcess = false
                if !parsed.isEmpty {
                    self.liveFetchedModels = parsed
                    AntigravitySDKModelFetcher.shared.updateModels(parsed)
                } else if !AntigravitySDKModelFetcher.shared.models.isEmpty {
                    self.liveFetchedModels = AntigravitySDKModelFetcher.shared.models
                }
            }
        }
    }

    // MARK: - Helpers
    private func selectThinkingLevel(_ level: ThinkingLevel) {
        selectedThinkingLevel = level

        // Auto-select premier model from the SDK matching this level
        let matching = activeModelsList.filter { $0.thinkingLevel.lowercased() == level.rawValue.lowercased() }
        if let preferred = matching.first {
            onSelect(preferred.id)
            AppSettings.shared.selectedAssistModelID = preferred.id
        }
    }

    private func syncThinkingLevelWithSelection() {
        if let currentModel = activeModelsList.first(where: { $0.id == selectedModelID }) {
            let lvl = currentModel.thinkingLevel.lowercased()
            if lvl == "high" {
                selectedThinkingLevel = .high
            } else if lvl == "low" {
                selectedThinkingLevel = .low
            } else {
                selectedThinkingLevel = .medium
            }
        }
    }

    private func formatContextWindow(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return "\(tokens / 1_000_000)M ctx"
        } else {
            return "\(tokens / 1_000)k ctx"
        }
    }
}
