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
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(recommendations) { recommendation in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(recommendation.modelName)
                                        .font(.headline)

                                    Text(recommendation.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Text("Compatibility: \(recommendation.compatibility)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    HStack {
                                        Text(recommendation.estimatedSize)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Download") {
                                            Task { await startRecommendedDownload(recommendation) }
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                }
                                .padding()
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(10)
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
                        } else {
                            ForEach(availableModels) { model in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(model.modelName)
                                        .font(.headline)
                                    Text(model.description)
                                        .font(.caption)
                                        .lineLimit(2)

                                    HStack {
                                        Text(model.modelSize)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
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
                                .padding()
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(10)
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
