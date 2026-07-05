import SwiftUI

struct DeploymentsView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @StateObject private var logManager = LogManager.shared
    @State private var selectedPlatform: DeploymentPlatform = .netlify
    @State private var customDomain: String = ""
    @State private var useCustomDomain: Bool = false
    @State private var isDeploying: Bool = false
    @State private var deploymentURL: String?
    @State private var errorMessage: String?

    private var hasToken: Bool {
        let service: APIKeyProvider = {
            switch selectedPlatform {
            case .netlify: return .netlify
            case .vercel: return .vercel
            case .githubPages: return .gitHub
            }
        }()
        return APIKeyManager.shared.retrieveKey(service: service) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Platform") {
                    Picker("Platform", selection: $selectedPlatform) {
                        ForEach(DeploymentPlatform.allCases) { platform in
                            Text(platform.rawValue).tag(platform)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Configuration") {
                    Toggle("Use Custom Domain", isOn: $useCustomDomain)
                    if useCustomDomain {
                        TextField("Type Custom Domain", text: $customDomain)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                Section {
                    Button(action: startDeployment) {
                        HStack {
                            if isDeploying {
                                ProgressView().padding(.trailing, 8)
                            } else {
                                Image(systemName: "cloud.fill")
                            }
                            Text(isDeploying ? "Deploying..." : "Start Deployment")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isDeploying || !hasToken)
                    .listRowBackground(isDeploying || !hasToken ? Color.gray.opacity(0.2) : Color.orange)
                    .foregroundStyle(.white)
                } footer: {
                    if !hasToken {
                        Text("Please configure your API key in Settings.")
                            .foregroundStyle(.red)
                    }
                }

                if let deploymentURL = deploymentURL {
                    Section("Result") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Deployment Successful")
                                .font(.subheadline.bold())
                        }

                        Link(destination: URL(string: deploymentURL)!) {
                            Label(deploymentURL, systemImage: "link")
                                .font(.caption.monospaced())
                        }

                        Button("Open In Browser") {
                            #if os(iOS)
                            UIApplication.shared.open(URL(string: deploymentURL)!)
                            #endif
                        }
                    }
                }

                if let errorMessage = errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    } header: {
                        Text("Error").foregroundStyle(.red)
                    }
                }

                if !logManager.deploymentLogs.isEmpty {
                    Section("Deployment Logs") {
                        DeploymentLogsView(logs: logManager.deploymentLogs)
                            .frame(height: 200)
                            .listRowInsets(EdgeInsets())
                    }
                }
            }
            .navigationTitle("Deployments")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func startDeployment() {
        guard let project = projectManager.activeProject else { return }

        isDeploying = true
        deploymentURL = nil
        errorMessage = nil
        logManager.clearDeploymentLogs()

        Task {
            do {
                let service: APIKeyProvider = {
                    switch selectedPlatform {
                    case .netlify: return .netlify
                    case .vercel: return .vercel
                    case .githubPages: return .gitHub
                    }
                }()
                let tokenToUse = APIKeyManager.shared.retrieveKey(service: service)

                let result = try await DeploymentTargets.shared.deploy(
                    project: project,
                    platform: selectedPlatform,
                    token: tokenToUse,
                    domain: useCustomDomain ? customDomain : nil
                ) { message in
                    DispatchQueue.main.async {
                        logManager.logDeployment(message)
                    }
                }

                DispatchQueue.main.async {
                    isDeploying = false
                    if result.success {
                        deploymentURL = result.url
                    } else {
                        errorMessage = result.errorMessage
                        logManager.logDeployment(result.errorMessage ?? "Unknown Error", isError: true)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isDeploying = false
                    errorMessage = error.localizedDescription
                    logManager.logDeployment(error.localizedDescription, isError: true)
                }
            }
        }
    }
}

#Preview {
    DeploymentsView()
        .environmentObject(ProjectManager.shared)
}
