import SwiftUI

struct OfflineModelsView: View {
    @StateObject private var manager = OfflineModelManager.shared
    @ObservedObject private var downloader = OfflineModelDownloader.shared
    @State private var availableModels: [OfflineModelMetadata] = []
    @State private var recommendations: [RecommendedOfflineModel] = []
    @State private var isLoading = false
    @State private var isRefreshingFromAPI = false
    @State private var downloadingModel: OfflineModelMetadata?
    @State private var isPresentingInstallGuide = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Installed Models
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Installed Models", systemImage: "externaldrive.fill")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                        }

                        InstalledOfflineModelsView(manager: manager)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 2. Recommended Models
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Recommended Models", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundColor(.purple)
                            Spacer()
                        }

                        if recommendations.isEmpty {
                            Text("No Recommendations Available")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(recommendations) { recommendation in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text(recommendation.modelName)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Spacer()

                                            Text(recommendation.estimatedSize)
                                                .font(.caption.bold())
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                                .foregroundStyle(.purple)
                                        }

                                        Text(recommendation.description)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)

                                        HStack {
                                            Label("Compatibility: \(recommendation.compatibility)", systemImage: "cpu")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Button("Download") {
                                                Task { await startRecommendedDownload(recommendation) }
                                            }
                                            .buttonStyle(.borderedProminent)
                                        }
                                    }
                                    .padding(14)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 3. Install Model via Link
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Install Model via Link", systemImage: "link")
                                .font(.headline)
                                .foregroundColor(.orange)
                            Spacer()
                        }

                        Text("You can download and install GGUF or CoreML models directly from custom URLs or Hugging Face links.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button("Install Model Through Link") {
                            isPresentingInstallGuide = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 4. Available Models on Hugging Face
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Available Models", systemImage: "arrow.down.circle")
                                .font(.headline)
                                .foregroundColor(.green)
                            Spacer()

                            Button {
                                Task {
                                    await loadModels(forceRefresh: true)
                                }
                            } label: {
                                Label("Fetch", systemImage: "arrow.clockwise")
                            }
                            .disabled(isLoading || isRefreshingFromAPI)
                        }

                        if isRefreshingFromAPI || isLoading {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Fetching available models...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 12)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(availableModels) { model in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text(model.modelName)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Spacer()

                                            Text(model.modelSize)
                                                .font(.caption.bold())
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                                .foregroundStyle(.green)
                                        }

                                        Text(model.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)

                                        HStack {
                                            if model.isQuantized {
                                                Label("Quantized", systemImage: "scalemass")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Button {
                                                startDownload(model)
                                            } label: {
                                                Text("Download")
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(manager.isModelInstalled(model.modelName) || model.preferredDownloadFile == nil)
                                        }
                                    }
                                    .padding(14)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .navigationTitle("Offline Models")
        .task {
            manager.loadInstalledModels()
            recommendations = DeviceCapabilityAnalyzer.shared.getRecommendedModelList()
            await loadModels(forceRefresh: false)
        }
        .sheet(item: $downloadingModel) { model in
            ModelDownloadProgressView(
                modelName: model.modelName,
                modelLink: model.modelURL.absoluteString,
                metadata: model
            ) {
                downloadingModel = nil
                await loadModels(forceRefresh: false)
            }
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isPresentingInstallGuide) {
            ModelLinkInstallGuideView {
                await loadModels(forceRefresh: false)
            }
        }
    }

    private func loadModels(forceRefresh: Bool) async {
        isLoading = !forceRefresh
        isRefreshingFromAPI = forceRefresh
        do {
            availableModels = try await HuggingFaceAPI.shared.fetchModels(forceRefresh: forceRefresh)
        } catch {
            print("Failed to fetch models: \(error)")
        }
        isLoading = false
        isRefreshingFromAPI = false
    }

    private func startDownload(_ model: OfflineModelMetadata) {
        downloader.startDownload(model: model)
        downloadingModel = model
    }

    private func startRecommendedDownload(_ recommendation: RecommendedOfflineModel) async {
        do {
            let metadata = try await manager.fetchModelMetadataFromLink(recommendation.suggestedLink)
            downloader.startDownload(model: metadata)
            downloadingModel = metadata
        } catch {
            print("Failed to start recommended model download: \(error)")
        }
    }
}
