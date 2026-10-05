import SwiftUI

public struct CreateNewAppAdvancedView: View {
    @Binding public var config: CreateAppConfiguration

    public init(config: Binding<CreateAppConfiguration>) {
        self._config = config
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("4. Advanced Engineering Settings")
                .font(.title2.bold())

            Form {
                Section("Architecture & Tooling") {
                    TextField("Swift Compatibility Version:", text: $config.swiftVersion)
                    TextField("Architecture Pattern:", text: $config.architecturePreference)
                }

                Section("Safety & Overwrite Behavior") {
                    Toggle("Overwrite existing project metadata if project exists", isOn: $config.overwriteExistingMetadata)
                }

                Section("Build & Testing Pipeline") {
                    Toggle("Generate XCTest Unit Testing Suite", isOn: $config.createTests)
                    Toggle("Automatically run test suite after implementation", isOn: $config.runTestsAfterImplementation)
                    Toggle("Build project executable / app after completion", isOn: $config.buildAfterImplementation)
                }
            }
            .formStyle(.grouped)

            Spacer()
        }
    }
}
