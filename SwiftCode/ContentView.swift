import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var suggestionsManager: CodeSuggestionsML
    @ObservedObject private var downloader = OfflineModelDownloader.shared

    @State private var showSuggestionToast = false
    @State private var showSuggestionsView = false
    @State private var isShowingDownloadProgress = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let project = projectManager.activeProject {
                    ProjectWorkspaceView(project: project)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .trailing)
                        ))
                } else {
                    ProjectsDashboardView()
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading),
                            removal: .move(edge: .leading)
                        ))
                }
            }

        }
        .safeAreaInset(edge: .top) {
            if downloader.isDownloading, let model = downloader.activeModel {
                Button {
                    isShowingDownloadProgress = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Downloading \(model.modelName)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(downloader.progressLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: projectManager.activeProject?.id)
        .onChange(of: projectManager.activeProject?.id) {
            guard settings.codeSuggestionsEnabled, let project = projectManager.activeProject else { return }
            suggestionsManager.analyze(project: project)
        }
        .onChange(of: settings.codeSuggestionsEnabled) {
            guard settings.codeSuggestionsEnabled, let project = projectManager.activeProject else { return }
            suggestionsManager.analyze(project: project)
        }
        .sheet(isPresented: $showSuggestionsView) {
            CodeSuggestionsView()
                .environmentObject(suggestionsManager)
        }
        .fullScreenCover(isPresented: .init(get: { !settings.hasCompletedOnboarding }, set: { _ in })) {
            OnboardingView()
                .environmentObject(settings)
        }
        .sheet(isPresented: $isShowingDownloadProgress) {
            if let model = downloader.activeModel {
                ModelDownloadProgressView(
                    modelName: model.modelName,
                    modelLink: model.modelURL.absoluteString,
                    metadata: model,
                    onComplete: nil
                )
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
            }
        }
    }
}
