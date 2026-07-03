import SwiftUI

struct SettingsView: View {
    @State var viewModel = SettingsViewModel()

    var body: some View {
        TabView {
            Form {
                SecureField("OpenRouter API Key", text: $viewModel.openRouterKey)
                SecureField("GitHub PAT", text: $viewModel.githubPAT)
                Button("Save Keys") {
                    Task { await viewModel.saveKeys() }
                }
            }
            .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            .padding()

            Text("General Settings")
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 500, height: 300)
    }
}
