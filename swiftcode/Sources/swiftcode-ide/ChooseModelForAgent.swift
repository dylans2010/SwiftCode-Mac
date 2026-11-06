// STAGED PORT — SwiftCode-Legacy `SwiftCode/Views/Assist/ChooseModelForAgent.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: swiftcode-ide (`swiftcode/Sources/swiftcode-ide/ChooseModelForAgent.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - searchable model-chooser sheet
// ADAPTATIONS:
//   - Observation adaptation DEFERRED to wiring: view still uses @ObservedObject/@StateObject over ObservableObject models; destination swiftcode-ide uses @Observable (no ObservableObject anywhere) — adapt when the models land (A6 AssistManager et al.).
//   - Added `import SwiftCodeAssistant` (views consume Assist models; module is a swiftcode-ide dependency).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - AppSettings — UNOWNED (no worklist) (`SwiftCode/Models/AppSettings.swift`)
//   - AppleFoundationModel — UNOWNED (no worklist) (`SwiftCode/Services/FoundationModels.swift`)
//   - AssistModelFilter — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/AssistModels.swift`)
//   - DynamicModelOption — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/AssistModels.swift`)
//   - FoundationModels — UNOWNED (no worklist) (`SwiftCode/Services/FoundationModels.swift`)
//   - ModelCategory — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/AssistModels.swift`)
//   - OpenRouterService — UNOWNED (no worklist) (`SwiftCode/Services/OpenRouterService.swift`)
// WIRING / REGISTRATION: Wire into the swiftcode-ide assistant UI (AssistantPane / AssistMainView) once the models it observes land. Remaining in-file work: @Observable adaptation (see ADAPTATIONS).

import SwiftUI
import os
import SwiftCodeAssistant

private let logger = Logger(subsystem: "com.swiftcode.ChooseModelForAgent", category: "ChooseModelForAgent")


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
                Label("Choose Model", systemImage: "cpu")
                    .font(.headline)
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
            .liquidGlass(style: .subtle, cornerRadius: 8)
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
        let filter = AssistModelFilter.shared

        // 1. Apple Foundation Models
        if filter.isEnabled(AppleFoundationModel.afm3Core.rawValue) {
            modelsList.append(DynamicModelOption(
                modelID: AppleFoundationModel.afm3Core.rawValue,
                name: "Apple AFM 3 Core",
                provider: "Apple Private on-device reasoning",
                status: "On-Device",
                isAvailable: true,
                category: .apple
            ))
        }
        if filter.isEnabled(AppleFoundationModel.afm3CoreAdvanced.rawValue) {
            modelsList.append(DynamicModelOption(
                modelID: AppleFoundationModel.afm3CoreAdvanced.rawValue,
                name: "Apple AFM 3 Core Advanced",
                provider: "Apple Private on-device reasoning (voice)",
                status: "On-Device",
                isAvailable: true,
                category: .apple
            ))
        }

        // 2. HuggingFace Local Models
        let localModels = OfflineModelManager.shared.installedModels
        for m in localModels {
            if filter.isEnabled(m.modelName) {
                modelsList.append(DynamicModelOption(
                    modelID: m.modelName,
                    name: m.modelName,
                    provider: "HuggingFace Local",
                    status: "Downloaded",
                    isAvailable: true,
                    category: .local
                ))
            }
        }

        // 3. Custom endpoint/link models
        if !settings.customModel.isEmpty && filter.isEnabled(settings.customModel) {
            modelsList.append(DynamicModelOption(
                modelID: settings.customModel,
                name: "Custom (Endpoint)",
                provider: "Custom API Provider",
                status: "Cloud",
                isAvailable: true,
                category: .custom
            ))
        }

        // 4. OpenRouter Cloud Models are added from the live fetch below.

        self.dynamicModels = modelsList

        // Fetch live OpenRouter models asynchronously
        isFetching = true
        Task {
            do {
                let liveModels = try await OpenRouterService.shared.fetchModels()
                await MainActor.run {
                    var updatedList = self.dynamicModels.filter { $0.category != .openRouter }
                    for m in liveModels {
                        if filter.isEnabled(m.id) {
                            updatedList.append(DynamicModelOption(
                                modelID: m.id,
                                name: m.name,
                                provider: "OpenRouter Cloud",
                                status: "Cloud",
                                isAvailable: true,
                                category: .openRouter
                            ))
                        }
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
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? .primary : .primary)

                    Text(option.modelID)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(option.status)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
