import SwiftUI

public struct CreateNewAppMetadataView: View {
    @Binding public var config: CreateAppConfiguration

    public init(config: Binding<CreateAppConfiguration>) {
        self._config = config
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("2. Application Metadata & Target Platform")
                .font(.title2.bold())

            Form {
                Section("Identity") {
                    TextField("App Name:", text: $config.appName, prompt: Text("e.g. My Notes"))
                    TextField("Bundle Identifier:", text: $config.bundleIdentifier, prompt: Text("e.g. com.example.mynotes"))

                    HStack {
                        TextField("Version:", text: $config.version)
                            .frame(width: 120)
                        Spacer()
                        TextField("Build:", text: $config.build)
                            .frame(width: 120)
                    }
                }

                Section("Platform") {
                    Picker("Target Platform:", selection: $config.platform) {
                        ForEach(CreateAppPlatform.allCases) { platform in
                            Label(platform.rawValue, systemImage: platform.icon).tag(platform)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Location") {
                    HStack {
                        TextField("Project Directory:", text: $config.projectLocation)
                        Button("Browse…") {
                            selectFolder()
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Spacer()
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Location"

        if panel.runModal() == .OK, let url = panel.url {
            config.projectLocation = url.appendingPathComponent(config.appName.isEmpty ? "NewApp" : config.appName).path
        }
    }
}
