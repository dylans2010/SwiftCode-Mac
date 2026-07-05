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
        List {
            InstalledOfflineModelsView(manager: manager)

            Section("Recommended Models") {
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
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                }
            }

            Section("Install Model Through Link") {
                Button("Install Model Through Link") {
                    isPresentingInstallGuide = true
                }
            }

            Section("Available Models") {
                Button {
                    Task {
                        await loadModels(forceRefresh: true)
                    }
                } label: {
                    HStack {
                        Label("Fetch", systemImage: "arrow.clockwise")
                        if isRefreshingFromAPI {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                    }
                }
                .disabled(isLoading || isRefreshingFromAPI)

                if isLoading {
                    ProgressView()
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
                                Spacer()
                                Button {
                                    startDownload(model)
                                } label: {
                                    Text("Download")
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 4)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                                .disabled(manager.isModelInstalled(model.modelName) || model.preferredDownloadFile == nil)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
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
