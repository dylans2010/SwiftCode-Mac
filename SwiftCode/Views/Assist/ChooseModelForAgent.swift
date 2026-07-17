import SwiftUI
import os

private let logger = Logger(subsystem: "com.swiftcode.ChooseModelForAgent", category: "ChooseModelForAgent")

public struct DynamicModelOption: Identifiable, Hashable {
    public var id: String { modelID }
    public let modelID: String
    public let name: String
    public let provider: String
    public let status: String
    public let isAvailable: Bool
    public let category: ModelCategory

    public enum ModelCategory: String, CaseIterable, Sendable {
        case apple = "Apple Foundation Models"
        case local = "HuggingFace Local Models"
        case openRouter = "OpenRouter Cloud Models"
        case custom = "Custom Models"
    }
}

@MainActor
public struct ChooseModelForAgent: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = AppSettings.shared
    private var foundationModels = FoundationModels.shared
    @ObservedObject private var assistModelManager = AssistModelManager.shared

    @State private var searchText: String = ""
    @State private var dynamicModels: [DynamicModelOption] = []
    @State private var isFetching = false

    public init() {}

    private var currentActiveModelID: String {
        if foundationModels.isEnabled {
            return foundationModels.selectedModel.rawValue
        }
        return assistModelManager.customModelID.isEmpty ? settings.selectedModel : assistModelManager.customModelID
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Choose Task Model", systemImage: "cpu")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                if isFetching {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.trailing, 4)
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.thinMaterial)

            Divider()

            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .padding()

            Divider()

            // Models List
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let categories = DynamicModelOption.ModelCategory.allCases
                    ForEach(categories, id: \.self) { category in
                        let filtered = filteredModels(for: category)
                        if !filtered.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(category.rawValue.uppercased())
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)

                                ForEach(filtered) { option in
                                    modelRow(for: option)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .frame(maxHeight: 380)
        }
        .frame(width: 360)
        .onAppear {
            loadModels()
        }
    }

    private func filteredModels(for category: DynamicModelOption.ModelCategory) -> [DynamicModelOption] {
        let modelsInCategory = dynamicModels.filter { $0.category == category }
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return modelsInCategory
        }
        return modelsInCategory.filter {
            $0.name.lowercased().contains(searchText.lowercased()) ||
            $0.modelID.lowercased().contains(searchText.lowercased())
        }
    }

    private func loadModels() {
        var modelsList: [DynamicModelOption] = []

        // 1. Apple Foundation Models
        modelsList.append(DynamicModelOption(
            modelID: AppleFoundationModel.afm3Core.rawValue,
            name: "Apple AFM 3 Core",
            provider: "Apple Private on-device reasoning",
            status: "On-Device",
            isAvailable: true,
            category: .apple
        ))
        modelsList.append(DynamicModelOption(
            modelID: AppleFoundationModel.afm3CoreAdvanced.rawValue,
            name: "Apple AFM 3 Core Advanced",
            provider: "Apple Private on-device reasoning (voice)",
            status: "On-Device",
            isAvailable: true,
            category: .apple
        ))

        // 2. HuggingFace Local Models
        let localModels = OfflineModelManager.shared.installedModels
        for m in localModels {
            modelsList.append(DynamicModelOption(
                modelID: m.modelName,
                name: m.modelName,
                provider: "HuggingFace Local",
                status: "Downloaded",
                isAvailable: true,
                category: .local
            ))
        }

        // 3. Custom endpoint/link models
        if !settings.customModel.isEmpty {
            modelsList.append(DynamicModelOption(
                modelID: settings.customModel,
                name: "Custom (Endpoint)",
                provider: "Custom API Provider",
                status: "Cloud",
                isAvailable: true,
                category: .custom
            ))
        }

        // 4. OpenRouter Cloud Models (Fallback Presets)
        let openRouterPresets = [
            ("openai/gpt-4o", "GPT-4o"),
            ("anthropic/claude-3.5-sonnet", "Claude 3.5 Sonnet"),
            ("google/gemini-2.5-pro", "Gemini 2.5 Pro"),
            ("meta-llama/llama-3-70b-instruct", "Llama 3 70B"),
            ("openai/gpt-4o-mini", "GPT-4o Mini")
        ]
        for preset in openRouterPresets {
            modelsList.append(DynamicModelOption(
                modelID: preset.0,
                name: preset.1,
                provider: "OpenRouter Cloud",
                status: "Cloud",
                isAvailable: true,
                category: .openRouter
            ))
        }

        self.dynamicModels = modelsList

        // Fetch live OpenRouter models asynchronously
        isFetching = true
        Task {
            do {
                let liveModels = try await OpenRouterService.shared.fetchModels()
                await MainActor.run {
                    var updatedList = self.dynamicModels.filter { $0.category != .openRouter }
                    for m in liveModels {
                        updatedList.append(DynamicModelOption(
                            modelID: m.id,
                            name: m.name,
                            provider: "OpenRouter Cloud",
                            status: "Cloud",
                            isAvailable: true,
                            category: .openRouter
                        ))
                    }
                    self.dynamicModels = updatedList
                    self.isFetching = false
                }
            } catch {
                logger.warning("[loadModels] Failed to fetch live OpenRouter models, using preset fallbacks.")
                await MainActor.run {
                    self.isFetching = false
                }
            }
        }
    }

    private func selectModel(_ option: DynamicModelOption) {
        logger.log("[selectModel] Selecting model: \(option.modelID)")

        if option.category == .apple {
            foundationModels.isEnabled = true
            if let appleModel = AppleFoundationModel(rawValue: option.modelID) {
                foundationModels.selectedModel = appleModel
            }
        } else {
            foundationModels.isEnabled = false
            settings.selectedModel = option.modelID
            assistModelManager.customModelID = option.modelID
        }

        dismiss()
    }

    @ViewBuilder
    private func modelRow(for option: DynamicModelOption) -> some View {
        let isSelected = (option.modelID == currentActiveModelID)

        Button {
            selectModel(option)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(option.name)
                            .font(.subheadline.bold())
                            .foregroundColor(isSelected ? .orange : .primary)

                        Text(option.status)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                            .foregroundColor(.orange)
                    }

                    Text(option.modelID)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isSelected ? Color.orange.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
