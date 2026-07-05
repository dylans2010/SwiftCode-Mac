import SwiftUI

struct AppDetailsInfo: View {
    @Binding var appName: String
    @Binding var bundleIdentifier: String
    @Binding var marketingVersion: String
    @Binding var buildVersion: String
    @Binding var supportedDevices: String

    let onSkip: () -> Void
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("App Metadata") {
                    TextField("App Name", text: $appName)
                    TextField("Bundle Identifier", text: $bundleIdentifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("App Version", text: $marketingVersion)
                    TextField("Build Version", text: $buildVersion)
                }

                Section("Supported Devices") {
                    Picker("Devices", selection: $supportedDevices) {
                        Text("iPhone").tag("iPhone")
                        Text("iPad").tag("iPad")
                        Text("iPhone + iPad").tag("iPhone + iPad")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("App Details")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") { onSkip() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start Compile") { onContinue() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
