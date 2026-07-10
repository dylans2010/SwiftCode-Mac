import AppKit
import SwiftUI

struct DeploymentsView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
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
            ScrollView {
                VStack(spacing: 24) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Deployment Platform", systemImage: "cloud.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            Picker("Platform", selection: $selectedPlatform) {
                                ForEach(DeploymentPlatform.allCases) { platform in
                                    Text(platform.rawValue).tag(platform)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding()
                    }
                    .groupBoxStyle(PreferencesGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Configuration", systemImage: "gearshape")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            Toggle("Use Custom Domain", isOn: $useCustomDomain)
                            if useCustomDomain {
                                TextField("Type Custom Domain", text: $customDomain)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(PreferencesGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Action", systemImage: "play.circle")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            Button(action: startDeployment) {
                                HStack {
                                    if isDeploying {
                                        ProgressView().scaleEffect(0.8).padding(.trailing, 8)
                                    } else {
                                        Image(systemName: "cloud.fill")
                                    }
                                    Text(isDeploying ? "Deploying..." : "Start Deployment")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isDeploying || !hasToken)

                            if !hasToken {
                                Text("Please configure your API key in Settings.")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(PreferencesGroupBoxStyle())

                    if let deploymentURL = deploymentURL {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
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
                                    NSWorkspace.shared.open(URL(string: deploymentURL)!)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding()
                        }
                        .groupBoxStyle(PreferencesGroupBoxStyle())
                    }

                    if let errorMessage = errorMessage {
                        GroupBox {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .padding()
                        }
                        .groupBoxStyle(PreferencesGroupBoxStyle())
                    }

                    if !logManager.deploymentLogs.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Deployment Logs", systemImage: "doc.text")
                                    .font(.headline)
                                    .foregroundColor(.gray)

                                DeploymentLogsView(logs: logManager.deploymentLogs)
                                    .frame(height: 200)
                                    .cornerRadius(8)
                            }
                            .padding()
                        }
                        .groupBoxStyle(PreferencesGroupBoxStyle())
                    }
                }
                .padding(24)
            }
            .navigationTitle("Deployments")
        }
    }

    private func startDeployment() {
        guard let project = sessionStore.activeProject else { return }

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
                ) { @Sendable message in
                    Task { @MainActor in
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
